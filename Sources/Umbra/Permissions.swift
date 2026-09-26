import AppKit
import CoreLocation
import SwiftUI

/// Explains a permission in plain words before macOS shows its own prompt.
/// Each explainer says what the permission is for, what Umbra does with it, and what happens if you say no.
enum Permissions {
    enum Choice { case primary, secondary, cancel }

    struct Point: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let text: String
    }

    struct Content {
        var symbol: String
        var tint: Color
        var title: String
        var intro: String
        var points: [Point]
        var primary: String
        var secondary: String?
        var cancel = "Not now"
        var urlField = false
    }

    // MARK: Explainers

    static func sensor() -> Content {
        Content(
            symbol: "sensor.fill", tint: .orange,
            title: "Sensor mode uses a light sensor on your network",
            intro: "Sensor mode sets brightness from a light sensor near your desk. The sensor is a small Wi-Fi device (for example, an ESP32 board) that reports how bright the room is.",
            points: [
                Point(symbol: "network", title: "Why macOS asks",
                      text: "Umbra reads the sensor over your local network. macOS will ask if Umbra can find and connect to devices on your local network."),
                Point(symbol: "lock.shield", title: "What Umbra does",
                      text: "Umbra asks only the address you enter below for the light level, every 2 seconds. It doesn't scan your network or send anything to the internet."),
                Point(symbol: "hand.raised", title: "If you say no",
                      text: "Sensor mode can't read the sensor. Everything else keeps working. You can change this later in System Settings > Privacy & Security > Local Network."),
                Point(symbol: "arrow.triangle.2.circlepath", title: "No sensor?",
                      text: "Use Sync mode. It follows your Mac's built-in light sensor and needs no permission."),
            ],
            primary: "Use this sensor", secondary: "Use Sync mode", cancel: "Cancel", urlField: true
        )
    }

    static func location(denied: Bool) -> Content {
        Content(
            symbol: "location.fill", tint: .blue,
            title: denied ? "Location access is off for Umbra" : "Location mode needs your location",
            intro: "Location mode dims your screens after sunset and brightens them after sunrise. To know when that happens where you are, Umbra needs your location.",
            points: [
                Point(symbol: "sun.horizon", title: "What Umbra does",
                      text: "Umbra saves only your latitude and longitude on this Mac and uses them to work out sunrise and sunset. It doesn't track you or send your location anywhere."),
                Point(symbol: "hand.raised", title: "If you say no",
                      text: "You can type your coordinates in Settings > Modes instead. Location mode works the same way with typed coordinates."),
            ] + (denied ? [Point(symbol: "gearshape", title: "To turn it on",
                                 text: "Open System Settings > Privacy & Security > Location Services, then turn on Umbra.")] : []),
            primary: denied ? "Open System Settings" : "Continue", secondary: "Type coordinates", cancel: "Cancel"
        )
    }

    static func accessibility(forCleaning: Bool) -> Content {
        Content(
            symbol: "keyboard", tint: .purple,
            title: forCleaning ? "Cleaning Mode needs Accessibility access" : "Let your brightness and volume keys control monitors",
            intro: forCleaning
                ? "Cleaning Mode blocks the keyboard so you can wipe it. To block keys, Umbra needs Accessibility access."
                : "Umbra needs Accessibility access to notice when you press the brightness and volume keys. Then those keys can control your external monitors.",
            points: [
                Point(symbol: "lock.shield", title: "What Umbra does",
                      text: "Umbra reacts only to brightness keys, volume keys, and your Umbra hotkeys. It doesn't record or save what you type."),
                Point(symbol: "hand.raised", title: "If you say no",
                      text: "Sliders, hotkeys, and all modes still work. Only the keyboard's brightness and volume keys won't control external monitors, and Cleaning Mode can't block keys."),
                Point(symbol: "gearshape", title: "What happens next",
                      text: "macOS opens System Settings > Privacy & Security > Accessibility. Turn on Umbra in the list."),
            ],
            primary: "Open System Settings", secondary: nil
        )
    }

    // MARK: Presenting

    private static var panel: NSPanel?

    /// Shows the explainer in a floating window and calls `completion` with the choice and the address field text.
    /// It does not block the app: a blocking modal stops SwiftUI from drawing buttons and handling clicks.
    static func present(_ content: Content, url: String = "", completion: @escaping (Choice, String) -> Void) {
        panel?.orderOut(nil)
        let model = PanelModel(url: url)
        let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 460, height: 400), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.hidesOnDeactivate = false
        var finished = false
        let finish: (Choice) -> Void = { choice in
            guard !finished else { return }
            finished = true
            p.orderOut(nil)
            if panel === p { panel = nil }
            completion(choice, model.url.trimmingCharacters(in: .whitespaces))
        }
        let host = NSHostingView(rootView: PermissionView(content: content, model: model, done: finish))
        p.contentView = host
        p.setContentSize(host.fittingSize)
        p.center()
        // Closing with the red button counts as Cancel.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { _ in finish(.cancel) }
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Flows

    /// Asks for Accessibility with an explanation first. Returns true if access is already on.
    @discardableResult
    static func ensureAccessibility(forCleaning: Bool = false) -> Bool {
        if MediaKeys.shared.trusted { return true }
        present(accessibility(forCleaning: forCleaning)) { choice, _ in
            guard choice == .primary else { return }
            MediaKeys.shared.requestAccess()
            openPrivacyPane("Privacy_Accessibility")
        }
        return false
    }

    /// Calls `ready(true)` when Location mode can start.
    static func prepareLocation(_ ready: @escaping (Bool) -> Void) {
        let s = AppState.shared
        if s.settings.hasLocation { ready(true); return }
        let status = CLLocationManager().authorizationStatus
        if status == .authorized || status == .authorizedAlways {
            Engine.shared.requestLocation()
            ready(true)
            return
        }
        let denied = status == .denied || status == .restricted
        present(location(denied: denied)) { choice, _ in
            switch choice {
            case .primary:
                if denied { openPrivacyPane("Privacy_LocationServices"); ready(false); return }
                Engine.shared.requestLocation()
                ready(true)
            case .secondary:
                (NSApp.delegate as? AppDelegate)?.openSettings(tab: "modes")
                ready(false)
            case .cancel:
                ready(false)
            }
        }
    }

    /// Calls `next` with the mode to switch to: sensor, sync, or nil to stay put.
    static func prepareSensor(_ next: @escaping (AdaptiveMode?) -> Void) {
        let s = AppState.shared
        present(sensor(), url: s.settings.sensorURL) { choice, url in
            switch choice {
            case .primary:
                guard !url.isEmpty else { next(nil); return }
                s.settings.sensorURL = url
                s.settings.sensorConfirmed = true
                next(.sensor)
            case .secondary: next(.sync)
            case .cancel: next(nil)
            }
        }
    }
}

final class PanelModel: ObservableObject {
    @Published var url: String
    init(url: String) { self.url = url }
}

struct PermissionView: View {
    let content: Permissions.Content
    @ObservedObject var model: PanelModel
    let done: (Permissions.Choice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: content.symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(content.tint)
                    .frame(width: 44, height: 44)
                    .background(content.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 6) {
                    Text(content.title).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(content.intro).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(content.points) { p in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: p.symbol).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.title).font(.system(size: 12.5, weight: .semibold))
                            Text(p.text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            if content.urlField {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sensor address").font(.system(size: 12, weight: .medium))
                    TextField("http://umbra-sensor.local/lux", text: $model.url).textFieldStyle(.roundedBorder)
                    Text("The sensor must answer with the light level in lux, as a number or JSON.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button(content.cancel) { done(.cancel) }.keyboardShortcut(.cancelAction)
                Spacer()
                if let s = content.secondary { Button(s) { done(.secondary) } }
                Button(content.primary) { done(.primary) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(content.urlField && model.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(width: 460)
    }
}
