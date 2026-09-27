import AppKit
import Combine
import CoreGraphics
import Foundation

struct DisplayModeOption: Identifiable, Hashable {
    let mode: CGDisplayMode
    var id: String { "\(mode.width)x\(mode.height)@\(mode.refreshRate)-\(mode.pixelWidth)-\(mode.ioDisplayModeID)" }
    var label: String {
        let hz = mode.refreshRate > 0 ? String(format: " @ %.0fHz", mode.refreshRate) : ""
        let hidpi = mode.pixelWidth > mode.width ? " HiDPI" : ""
        return "\(mode.width) × \(mode.height)\(hz)\(hidpi)"
    }
    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

final class Display: ObservableObject, Identifiable {
    let id: CGDirectDisplayID
    let uuid: String
    let isBuiltin: Bool
    @Published var name: String
    @Published var config: DisplayConfig { didSet { if config != oldValue { save() } } }
    @Published var blackedOut = false
    /// Set by Away mode while the screens are turned black.
    var awayBlack = false
    @Published var inputSource: UInt16?
    @Published var ddcResponsive: Bool?
    var link: AVLink?

    private var maxValues: [VCP: UInt16] = [.brightness: 100, .contrast: 100, .volume: 100]
    private var pending: [VCP: UInt16] = [:]
    private var flushing = false
    private let lock = NSLock()
    private var animation: Timer?
    private var brightnessTrack: SpringTrack?
    private var xdrOverlay: XDROverlay?

    init(id: CGDirectDisplayID, link: AVLink?) {
        self.id = id
        self.link = link
        isBuiltin = CGDisplayIsBuiltin(id) != 0
        if let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            uuid = CFUUIDCreateString(nil, u) as String
        } else {
            uuid = "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
        }
        let screenName = NSScreen.screens.first { $0.displayID == id }?.localizedName
        name = isBuiltin ? "Built-in Display" : (screenName ?? link?.name ?? "Display \(id)")
        config = Store.loadMerged("display.\(uuid)", fallback: DisplayConfig())
        inputSource = config.lastInput
        if let link { probeRange(link) }
        if method == .appleNative, let b = Private.getBrightness(id) {
            config.brightness = toUser(Double(b) * 100, .brightness)
        }
    }

    private func save() { Store.save("display.\(uuid)", config) }

    // MARK: Capabilities

    var method: ControlMethod {
        if config.method != .auto { return config.method }
        if isBuiltin || Private.canChangeBrightness(id) { return .appleNative }
        if link != nil { return .ddc }
        if !config.networkURL.isEmpty { return .network }
        return .gamma
    }

    var hasHardwareControls: Bool { method == .ddc || method == .network }
    var supportsXDR: Bool { XDROverlay.supports(id) }
    var canRotate: Bool { Rotation.canRotate(id) }

    // MARK: Value mapping

    private func range(_ vcp: VCP) -> (Double, Double) {
        switch vcp {
        case .brightness: return (config.minBrightness, config.maxBrightness)
        case .contrast: return (config.minContrast, config.maxContrast)
        default: return (0, 100)
        }
    }

    /// User value 0..100 -> hardware percent after min/max limits.
    private func toHardware(_ v: Double, _ vcp: VCP) -> Double {
        let (lo, hi) = range(vcp)
        return lo + (hi - lo) * max(0, min(100, v)) / 100
    }

    private func toUser(_ hw: Double, _ vcp: VCP) -> Double {
        let (lo, hi) = range(vcp)
        guard hi > lo else { return 0 }
        return max(0, min(100, (hw - lo) / (hi - lo) * 100))
    }

    // MARK: Setters

    func setBrightness(_ v: Double, animated: Bool = false) {
        let v = max(0, min(100, v))
        if animated, AppState.shared.settings.smoothTransitions, brightnessTrack != nil || abs(v - config.brightness) > 2 {
            // Each new target adds one spring, so a fade that is already running bends toward the new value.
            if brightnessTrack == nil { brightnessTrack = SpringTrack(config.brightness) }
            brightnessTrack?.retarget(v, at: SpringTrack.now)
            startBrightnessTicker()
            return
        }
        stopBrightnessTicker()
        config.brightness = v
        applyBrightness()
    }

    private func startBrightnessTicker() {
        guard animation == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tickBrightness() }
        RunLoop.main.add(t, forMode: .common)
        animation = t
    }

    private func tickBrightness() {
        guard let track = brightnessTrack else { stopBrightnessTicker(); return }
        let now = SpringTrack.now
        if track.isSettled(at: now) {
            config.brightness = max(0, min(100, track.target))
            stopBrightnessTicker()
        } else {
            config.brightness = max(0, min(100, track.value(at: now)))
        }
        applyBrightness()
    }

    private func stopBrightnessTicker() {
        animation?.invalidate()
        animation = nil
        brightnessTrack = nil
    }

    func setContrast(_ v: Double, animated: Bool = false) {
        let v = max(0, min(100, v))
        config.contrast = v
        write(.contrast, toHardware(v, .contrast))
    }

    func setVolume(_ v: Double) {
        config.volume = max(0, min(100, v))
        if config.muted, v > 0 { setMuted(false) }
        write(.volume, config.volume)
    }

    func setMuted(_ m: Bool) {
        config.muted = m
        write(.mute, m ? 1 : 2, raw: true)
    }

    func setSubzero(_ v: Double) {
        config.subzero = max(0, min(1, v))
        applyGamma()
    }

    func setColor(red: Double? = nil, green: Double? = nil, blue: Double? = nil) {
        if let r = red { config.red = r }
        if let g = green { config.green = g }
        if let b = blue { config.blue = b }
        applyGamma()
    }

    func setInput(_ input: UInt16) {
        inputSource = input
        config.lastInput = input
        write(.inputSource, Double(input), raw: true)
    }

    func setXDR(_ on: Bool) {
        config.xdr = on
        applyXDR()
    }

    func setXDRLevel(_ v: Double) {
        config.xdrLevel = max(0, min(1, v))
        applyXDR()
    }

    func applyXDR() {
        if config.xdr, supportsXDR, !blackedOut {
            if xdrOverlay == nil { xdrOverlay = XDROverlay(screenID: id) }
            // XDR needs the panel at full SDR brightness first.
            if method == .appleNative { Private.setBrightness(id, 1) }
            xdrOverlay?.show(level: config.xdrLevel)
        } else {
            xdrOverlay?.hide()
            xdrOverlay = nil
            if method == .appleNative { applyBrightness() }
        }
    }

    func powerOff(_ off: Bool) {
        write(.power, off ? 5 : 1, raw: true)
    }

    /// Send any VCP code (used by the CLI).
    func sendRaw(code: UInt8, value: UInt16) {
        guard let link else { return }
        DispatchQueue.global().async { DDC.write(link, code: code, value) }
    }

    func applyAll() {
        applyBrightness()
        if hasHardwareControls { write(.contrast, toHardware(config.contrast, .contrast)) }
        applyGamma()
        applyXDR()
    }

    func applyBrightness() {
        let hw = toHardware(config.brightness, .brightness)
        switch method {
        case .appleNative:
            if !config.xdr { Private.setBrightness(id, Float(hw / 100)) }
        case .ddc, .network:
            write(.brightness, hw)
        case .gamma, .auto:
            applyGamma()
        }
    }

    func applyGamma() {
        var s = GammaController.State()
        if method == .gamma { s.factor = 0.12 + 0.88 * toHardware(config.brightness, .brightness) / 100 }
        if AppState.shared.settings.subzeroEnabled { s.factor *= 1 - 0.97 * config.subzero }
        if blackedOut, AppState.shared.settings.blackOutMethod == .soft { s.factor = 0 }
        if awayBlack { s.factor = 0 }
        s.red = config.red
        s.green = config.green
        s.blue = config.blue
        GammaController.shared.set(id, s)
    }

    private func write(_ vcp: VCP, _ percent: Double, raw: Bool = false) {
        switch method {
        case .network:
            let value = raw ? UInt16(percent) : UInt16((percent / 100 * 100).rounded())
            NetworkDDC.send(base: config.networkURL, vcp, value)
        case .ddc:
            let max = config.ddcMax > 0 ? UInt16(config.ddcMax) : (maxValues[vcp] ?? 100)
            let value = raw ? UInt16(percent) : DDC.hardwareValue(percent: percent, max: max)
            enqueue(vcp, value)
        default:
            if vcp == .brightness { applyGamma() }
        }
    }

    private func enqueue(_ vcp: VCP, _ value: UInt16) {
        guard let link else { return }
        lock.lock()
        pending[vcp] = value
        if flushing { lock.unlock(); return }
        flushing = true
        lock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var finals: [UInt8: UInt16] = [:]
            var batches = 0
            while let self {
                self.lock.lock()
                let batch = self.pending
                self.pending = [:]
                if batch.isEmpty {
                    // After a burst (a slider drag), re-send the final values once the monitor has settled,
                    // in case it ignored a command that came too soon after the one before.
                    if batches > 1, !finals.isEmpty {
                        self.lock.unlock()
                        DDC.settle(link, finals: finals)
                        finals = [:]
                        batches = 0
                        continue
                    }
                    self.flushing = false
                    self.lock.unlock()
                    return
                }
                self.lock.unlock()
                for (k, v) in batch { DDC.write(link, k, v); finals[k.rawValue] = v }
                batches += 1
            }
        }
    }

    /// Give a display its DDC link after it's already showing, for example when the link appears late after a reconnect.
    func attach(_ link: AVLink) {
        self.link = link
        objectWillChange.send()
        probeRange(link)
        applyAll()
    }

    /// Learn each control's real maximum once, in the background, then re-send the current values scaled to it.
    /// Without this, a monitor whose brightness goes to 255 would top out at 100/255 (about 39%).
    private func probeRange(_ link: AVLink) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = DDC.probeMax(link)
            guard !found.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                var changed = false
                for (vcp, mx) in found where self.maxValues[vcp] != mx { self.maxValues[vcp] = mx; changed = true }
                if changed, self.method == .ddc { self.applyAll() }
            }
        }
    }

    /// Read current values from the monitor so sliders start where the monitor is.
    func readHardware(force: Bool = false) {
        guard let link, config.readDDC || force, config.method == .auto || config.method == .ddc else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let b = DDC.read(link, .brightness)
            let c = DDC.read(link, .contrast)
            let v = DDC.read(link, .volume)
            let i = DDC.read(link, .inputSource)
            DispatchQueue.main.async {
                guard let self else { return }
                if b != nil || c != nil { self.ddcResponsive = true } else if self.ddcResponsive == nil { self.ddcResponsive = false }
                if let (cur, mx) = b, mx > 0 {
                    self.maxValues[.brightness] = mx
                    self.config.brightness = self.toUser(Double(cur) / Double(mx) * 100, .brightness)
                }
                if let (cur, mx) = c, mx > 0 {
                    self.maxValues[.contrast] = mx
                    self.config.contrast = self.toUser(Double(cur) / Double(mx) * 100, .contrast)
                }
                if let (cur, mx) = v, mx > 0 {
                    self.maxValues[.volume] = mx
                    self.config.volume = Double(cur) / Double(mx) * 100
                }
                if let (cur, _) = i { self.inputSource = cur & 0xFF }
            }
        }
    }

    /// Current brightness straight from the OS (Apple Native displays only).
    func readSystemBrightness() -> Double? {
        guard method == .appleNative, !config.xdr, let b = Private.getBrightness(id) else { return nil }
        return toUser(Double(b) * 100, .brightness)
    }

    // MARK: Resolution and rotation

    var modes: [DisplayModeOption] {
        let opts = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let all = (CGDisplayCopyAllDisplayModes(id, opts) as? [CGDisplayMode]) ?? []
        var seen = Set<String>()
        return all.filter { $0.isUsableForDesktopGUI() }
            .map(DisplayModeOption.init)
            .filter { seen.insert($0.label).inserted }
            .sorted { ($0.mode.width, $0.mode.refreshRate) > ($1.mode.width, $1.mode.refreshRate) }
    }

    var currentMode: DisplayModeOption? {
        guard let m = CGDisplayCopyDisplayMode(id) else { return nil }
        return DisplayModeOption(mode: m)
    }

    func setMode(_ option: DisplayModeOption) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        CGConfigureDisplayWithDisplayMode(cfg, id, option.mode, nil)
        CGCompleteDisplayConfiguration(cfg, .permanently)
        objectWillChange.send()
    }

    var rotation: Int { Int(CGDisplayRotation(id)) }

    func setRotation(_ degrees: Int) {
        Rotation.set(id, degrees: degrees)
        objectWillChange.send()
    }
}

/// Display rotation through the private MonitorPanel framework.
enum Rotation {
    private static let loaded: Bool = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_LAZY) != nil

    private static func mpDisplay(_ id: CGDirectDisplayID) -> NSObject? {
        guard loaded, let cls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else { return nil }
        let mgr = cls.init()
        guard let displays = mgr.value(forKey: "displays") as? [NSObject] else { return nil }
        return displays.first { ($0.value(forKey: "displayID") as? NSNumber)?.uint32Value == id }
    }

    static func canRotate(_ id: CGDirectDisplayID) -> Bool {
        guard let d = mpDisplay(id) else { return false }
        return (d.value(forKey: "canChangeOrientation") as? Bool) ?? false
    }

    static func set(_ id: CGDirectDisplayID, degrees: Int) {
        guard let d = mpDisplay(id) else { return }
        let sel = NSSelectorFromString("setOrientation:")
        guard d.responds(to: sel), let m = class_getInstanceMethod(type(of: d), sel) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector, Int32) -> Void
        let f = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        f(d, sel, Int32(degrees))
    }
}
