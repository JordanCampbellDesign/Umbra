import AppKit
import CoreGraphics
import Foundation
#if canImport(MetricKit)
import MetricKit
#endif

/// Opt-in, anonymous diagnostics so monitor problems on other people's Macs can be found and fixed.
///
/// Nothing is sent unless the user turns on "Share anonymous monitor diagnostics" AND the build has a
/// PostHog project key (Info.plist `UmbraPostHogKey`). What is sent:
/// - Umbra and macOS versions, the Mac model, and how many displays are connected.
/// - For each display: its model name and EDID vendor/product codes, how Umbra controls it, and whether a DDC link was found.
/// - DDC results per display and control: how many writes and reads worked or failed, the IOKit error code, noisy replies.
/// - Crash reports from macOS (MetricKit): exception type, signal, and the call stack of Umbra's own code.
/// Never sent: serial numbers, display names you set, window or screen contents, files, location, or anything you type.
final class Diagnostics: NSObject {
    static let shared = Diagnostics()

    private let key = (Bundle.main.object(forInfoDictionaryKey: "UmbraPostHogKey") as? String) ?? ""
    private let host = (Bundle.main.object(forInfoDictionaryKey: "UmbraPostHogHost") as? String) ?? "https://us.i.posthog.com"
    private var queue: [[String: Any]] = []
    private var ddcTally: [String: [String: Any]] = [:]
    private let lock = NSLock()
    private var flushTimer: Timer?

    /// True when this build can send diagnostics (it has a project key).
    var available: Bool { !key.isEmpty }
    var enabled: Bool { available && AppState.shared.settings.diagnosticsEnabled }

    /// A random ID for this install, so reports from one Mac can be grouped. Not tied to any account.
    var installID: String {
        let d = UserDefaults.standard
        if let id = d.string(forKey: "diagnosticsInstallID") { return id }
        let id = UUID().uuidString
        d.set(id, forKey: "diagnosticsInstallID")
        return id
    }

    func start() {
        #if canImport(MetricKit)
        if #available(macOS 12.0, *) { MXMetricManager.shared.add(self) }
        #endif
        let t = Timer(timeInterval: 600, repeats: true) { [weak self] _ in self?.flush() }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        flushTimer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.reportLaunch() }
    }

    // MARK: Events

    private func reportLaunch() {
        guard enabled else { return }
        capture("app_launched", [
            "display_count": AppState.shared.displays.count,
            "mac_model": Diagnostics.macModel,
        ])
        for d in AppState.shared.displays { capture("display_detected", Diagnostics.describe(d)) }
    }

    static func describe(_ d: Display) -> [String: Any] {
        [
            "model": d.isBuiltin ? "Built-in" : d.name,
            "vendor_code": Brand.code(CGDisplayVendorNumber(d.id)),
            "vendor_id": CGDisplayVendorNumber(d.id),
            "product_id": CGDisplayModelNumber(d.id),
            "control": d.method.rawValue,
            "ddc_link": d.link != nil,
            "builtin": d.isBuiltin,
            "pixels": "\(CGDisplayPixelsWide(d.id))x\(CGDisplayPixelsHigh(d.id))",
        ]
    }

    /// Called by DDC.write. Tallies results and reports them in batches instead of one event per write.
    func ddcWrite(link: AVLink, code: UInt8, ok: Bool, status: IOReturn) {
        tally(link: link, code: code) { t in
            t[ok ? "writes_ok" : "writes_failed", default: 0] = ((t[ok ? "writes_ok" : "writes_failed"] as? Int) ?? 0) + 1
            if !ok { t["last_error"] = String(format: "0x%08X", UInt32(bitPattern: status)) }
        }
    }

    /// Called by DDC.read.
    func ddcRead(link: AVLink, code: UInt8, ok: Bool, noisyReplies: Int) {
        tally(link: link, code: code) { t in
            t[ok ? "reads_ok" : "reads_failed", default: 0] = ((t[ok ? "reads_ok" : "reads_failed"] as? Int) ?? 0) + 1
            t["noisy_replies"] = ((t["noisy_replies"] as? Int) ?? 0) + noisyReplies
        }
    }

    private func tally(link: AVLink, code: UInt8, _ update: (inout [String: Any]) -> Void) {
        guard enabled else { return }
        let id = "\(link.name ?? "unknown")|\(code)"
        lock.lock(); defer { lock.unlock() }
        var t = ddcTally[id] ?? ["model": link.name ?? "unknown", "vendor_id": link.vendor ?? 0, "product_id": link.product ?? 0,
                                 "vcp": String(format: "0x%02X", code)]
        update(&t)
        ddcTally[id] = t
    }

    /// Report something that went wrong outside DDC, for example BlackOut failing to disconnect a display.
    func failure(_ what: String, _ props: [String: Any] = [:]) {
        guard enabled else { return }
        capture("failure", props.merging(["what": what]) { a, _ in a })
    }

    func capture(_ event: String, _ props: [String: Any]) {
        guard enabled else { return }
        var p = props
        p["umbra_version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?"
        p["macos"] = ProcessInfo.processInfo.operatingSystemVersionString
        p["$process_person_profile"] = false          // anonymous events only
        lock.lock()
        queue.append(["event": event, "distinct_id": installID, "properties": p,
                      "timestamp": ISO8601DateFormatter().string(from: Date())])
        lock.unlock()
    }

    // MARK: Sending

    /// Send queued events and DDC summaries. Called every 10 minutes and when Umbra quits.
    func flush(sync: Bool = false) {
        guard enabled else { lock.lock(); queue = []; ddcTally = [:]; lock.unlock(); return }
        lock.lock()
        for (_, t) in ddcTally where (t["writes_failed"] as? Int ?? 0) + (t["reads_failed"] as? Int ?? 0) > 0 || sync {
            queue.append(["event": "ddc_summary", "distinct_id": installID, "properties": t.merging(["$process_person_profile": false]) { a, _ in a },
                          "timestamp": ISO8601DateFormatter().string(from: Date())])
        }
        ddcTally = [:]
        let batch = queue
        queue = []
        lock.unlock()
        guard !batch.isEmpty, let url = URL(string: host + "/batch/"),
              let body = try? JSONSerialization.data(withJSONObject: ["api_key": key, "batch": batch]) else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, _, _ in done.signal() }.resume()
        if sync { _ = done.wait(timeout: .now() + 3) }
    }

    static var macModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &buf, &size, nil, 0)
        return String(cString: buf)
    }

    // MARK: Report a problem

    /// Text a person can paste into a GitHub issue. Always available, even with diagnostics off.
    func problemReport() -> String {
        var lines = ["Umbra \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "?")",
                     "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)", "Mac \(Diagnostics.macModel)", ""]
        for d in AppState.shared.displays {
            let x = Diagnostics.describe(d)
            lines.append("- \(x["model"]!): control \(x["control"]!), DDC link \(x["ddc_link"]!), vendor \(x["vendor_code"]!) (\(x["vendor_id"]!)), product \(x["product_id"]!), \(x["pixels"]!)")
        }
        return lines.joined(separator: "\n")
    }

    /// Open a new "Monitor compatibility" issue on GitHub with the report filled in.
    func openProblemReport() {
        var c = URLComponents(string: "https://github.com/JordanCampbellDesign/Umbra/issues/new")!
        c.queryItems = [URLQueryItem(name: "template", value: "monitor.yml"),
                        URLQueryItem(name: "title", value: "Monitor problem: "),
                        URLQueryItem(name: "debug", value: problemReport())]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }
}

#if canImport(MetricKit)
@available(macOS 12.0, *)
extension Diagnostics: MXMetricManagerSubscriber {
    /// macOS delivers crash reports for the previous run shortly after launch.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard enabled else { return }
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                capture("crash", [
                    "exception_type": crash.exceptionType?.intValue ?? -1,
                    "signal": crash.signal?.intValue ?? -1,
                    "termination_reason": crash.terminationReason ?? "",
                    "app_version": crash.metaData.applicationBuildVersion,
                    "call_stack": String(decoding: crash.callStackTree.jsonRepresentation(), as: UTF8.self).prefix(20000),
                ])
            }
        }
        flush()
    }
}
#endif
