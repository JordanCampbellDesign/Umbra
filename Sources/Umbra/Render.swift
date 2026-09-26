import AppKit
import SwiftUI

/// Dev helper: draws the menu and each Settings tab to PNG files (`umbra render <dir>`).
enum Render {
    static func run(_ dir: String) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        AppState.shared.refreshDisplays()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let dark = ProcessInfo.processInfo.environment["UMBRA_DARK"] != nil
        let views: [(String, AnyView, CGSize)] = [
            ("menu", AnyView(MenuView(openSettings: {})), CGSize(width: 380, height: 700)),
            ("settings-general", AnyView(GeneralTab().padding()), CGSize(width: 640, height: 560)),
            ("settings-modes", AnyView(ModesTab().padding()), CGSize(width: 640, height: 560)),
            ("settings-displays", AnyView(DisplaysTab().padding()), CGSize(width: 640, height: 560)),
            ("settings-hotkeys", AnyView(HotkeysTab().padding()), CGSize(width: 640, height: 560)),
            ("settings-presets", AnyView(PresetsTab().padding()), CGSize(width: 640, height: 560)),
            ("welcome", AnyView(OnboardingView {}), CGSize(width: 520, height: 900)),
            ("perm-sensor", AnyView(PermissionView(content: Permissions.sensor(), model: PanelModel(url: "")) { _ in }), CGSize(width: 460, height: 600)),
            ("perm-location", AnyView(PermissionView(content: Permissions.location(denied: false), model: PanelModel(url: "")) { _ in }), CGSize(width: 460, height: 600)),
            ("perm-keys", AnyView(PermissionView(content: Permissions.accessibility(forCleaning: false), model: PanelModel(url: "")) { _ in }), CGSize(width: 460, height: 600)),
            ("settings-about", AnyView(AboutTab().padding()), CGSize(width: 640, height: 560)),
        ]
        for (name, view, size) in views {
            let host = NSHostingView(rootView: view.frame(width: size.width).fixedSize(horizontal: false, vertical: name == "menu" || name.hasPrefix("perm") || name == "welcome")
                .background(Color(nsColor: .windowBackgroundColor)))
            let w = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            w.contentView = host
            if name == "menu" || name.hasPrefix("perm") || name == "welcome" { w.setContentSize(host.fittingSize) }
            w.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            w.orderOut(nil)
        }
        print("rendered to \(dir)")
        return 0
    }
}
