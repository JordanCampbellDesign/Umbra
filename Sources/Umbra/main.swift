import AppKit
import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var mainWindow: NSWindow?
    private var iconSub: AnyCancellable?
    private var lastIconKey = ""
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let b = statusItem.button {
            b.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "Umbra")
            b.action = #selector(togglePopover)
            b.target = self
        }
        iconSub = AppState.shared.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusIcon() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.updateStatusIcon() }
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: MenuView(openSettings: { [weak self] in self?.openSettings() }))
        AppState.shared.start()
        _ = Updater.shared
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        buildMainMenu()
        updateActivationPolicy()
        // Show the main window if asked to, or if the menu bar icon ends up hidden (for example behind the notch).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            if Onboarding.needed { Onboarding.show(); return }
            if CommandLine.arguments.contains("--window") || AppState.shared.settings.openWindowAtLaunch || !self.statusItemVisible {
                self.openMainWindow()
            }
        }
        // The welcome screen covers the keys, so only ask here for people who already finished it.
        if !Onboarding.needed, !MediaKeys.shared.trusted, !UserDefaults.standard.bool(forKey: "askedAccessibility") {
            UserDefaults.standard.set(true, forKey: "askedAccessibility")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { Permissions.ensureAccessibility() }
        }
    }

    func applicationWillTerminate(_: Notification) {
        AppState.shared.shutdown()
    }

    @objc func handleURL(_ event: NSAppleEventDescriptor, reply _: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue, let url = URL(string: s) else { return }
        CLI.handle(url: url)
    }

    /// Opening Umbra again from Finder, Spotlight, or the Dock shows the main window.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        openMainWindow()
        return false
    }

    /// Menu bar icon: a circle that fills from the bottom with the average brightness, or a moon in Night Mode.
    func updateStatusIcon() {
        let s = AppState.shared
        let on = s.displays.filter { !$0.blackedOut }
        let level = on.isEmpty ? 0 : on.map { $0.config.subzero > 0 ? 0 : $0.config.brightness }.reduce(0, +) / Double(on.count) / 100
        let key = NightMode.shared.on ? "night" : String(format: "%.2f", level)
        guard key != lastIconKey, let b = statusItem.button else { return }
        lastIconKey = key
        if NightMode.shared.on {
            b.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Umbra, Night Mode on")
            return
        }
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { r in
            let circle = NSBezierPath(ovalIn: r.insetBy(dx: 2.25, dy: 2.25))
            circle.lineWidth = 1.5
            NSColor.black.setStroke()
            circle.stroke()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: r.insetBy(dx: 4, dy: 4)).addClip()
            NSColor.black.setFill()
            let inner = r.insetBy(dx: 4, dy: 4)
            NSRect(x: inner.minX, y: inner.minY, width: inner.width, height: inner.height * CGFloat(max(0.08, level))).fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Umbra, brightness \(Int(level * 100))%"
        b.image = img
    }

    /// The menu bar icon's frame in screen coordinates, used for scroll-to-adjust.
    var statusItemScreenFrame: CGRect? {
        guard let b = statusItem.button, let w = b.window else { return nil }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }

    /// False when macOS hides the menu bar icon, for example when too many icons sit behind the notch.
    var statusItemVisible: Bool {
        guard let w = statusItem.button?.window else { return false }
        return w.occlusionState.contains(.visible) && NSScreen.screens.contains { $0.frame.intersects(w.frame) }
    }

    func openMainWindow() {
        popover.performClose(nil)
        if mainWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Umbra"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentView = NSHostingView(rootView: MenuView(openSettings: { [weak self] in self?.openSettings() }, inWindow: true)
                .padding(.top, 14)
                .background(VisualEffect().ignoresSafeArea()))
            w.contentMinSize = CGSize(width: 380, height: 420)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("UmbraMainWindow")
            if !w.setFrameUsingName("UmbraMainWindow") { w.center() }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.updateActivationPolicy() }
            }
            mainWindow = w
        }
        AppState.shared.refreshDisplays()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Show a Dock icon while a window is open, or always when the user asks for it.
    func updateActivationPolicy() {
        let windowOpen = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        NSApp.setActivationPolicy(AppState.shared.settings.showDockIcon || windowOpen ? .regular : .accessory)
    }

    /// App menu used while Umbra shows in the Dock, so ⌘W, ⌘Q, and ⌘, work.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Umbra", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        if Updater.shared.available {
            let upd = appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesAction), keyEquivalent: "")
            upd.target = self
        }
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Umbra", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Umbra", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let show = windowMenu.addItem(withTitle: "Umbra", action: #selector(openMainWindowAction), keyEquivalent: "0")
        show.target = self
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func openSettingsAction() { openSettings() }
    @objc private func checkForUpdatesAction() { Updater.shared.checkForUpdates() }
    @objc private func openMainWindowAction() { openMainWindow() }

    @objc func togglePopover() {
        if !statusItemVisible { openMainWindow(); return }
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            AppState.shared.refreshDisplays()
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func openSettings(tab: String) {
        UserDefaults.standard.set(tab, forKey: "settingsTab")
        openSettings()
    }

    func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 560), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            w.title = "Umbra Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.updateActivationPolicy() }
            }
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Window background that matches the popover material.
struct VisualEffect: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .popover
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

let args = Array(CommandLine.arguments.dropFirst())
if args.first == "--cli" {
    exit(CLI.main(Array(args.dropFirst())))
} else if let first = args.first, !first.hasPrefix("-") {
    exit(CLI.main(args))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
