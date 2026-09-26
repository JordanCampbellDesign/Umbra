import AppKit
import SwiftUI
import CoreGraphics
import IOKit.pwr_mgt

/// Screen layout actions: mirror, set main, swap, and side-by-side arrangements.
enum Arrangement {
    struct Snapshot { var origins: [CGDirectDisplayID: CGPoint]; var mirrors: [CGDirectDisplayID: CGDirectDisplayID] }

    static func snapshot() -> Snapshot {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        var s = Snapshot(origins: [:], mirrors: [:])
        for id in ids.prefix(Int(n)) {
            s.origins[id] = CGDisplayBounds(id).origin
            s.mirrors[id] = CGDisplayMirrorsDisplay(id)
        }
        return s
    }

    static func restore(_ s: Snapshot) {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return }
        for (id, m) in s.mirrors { CGConfigureDisplayMirrorOfDisplay(cfg, id, m) }
        for (id, o) in s.origins where s.mirrors[id] == kCGNullDirectDisplay {
            CGConfigureDisplayOrigin(cfg, id, Int32(o.x), Int32(o.y))
        }
        CGCompleteDisplayConfiguration(cfg, .permanently)
    }

    /// Applies a layout change, then asks the user to keep it. Without an answer it switches back after 15 seconds.
    private static func configure(_ body: (CGDisplayConfigRef?) -> Void) -> Bool {
        let before = snapshot()
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        body(cfg)
        let ok = CGCompleteDisplayConfiguration(cfg, .permanently) == .success
        if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { ArrangementConfirm.shared.show(revertTo: before) } }
        return ok
    }

    private static func active(_ ds: [Display]) -> [Display] {
        ds.filter { !$0.blackedOut && CGDisplayMirrorsDisplay($0.id) == kCGNullDirectDisplay }
    }

    /// Mirror every other display onto `source`.
    @discardableResult
    static func mirror(to source: Display, _ all: [Display]) -> Bool {
        configure { cfg in
            for d in all where d.id != source.id && !d.blackedOut {
                CGConfigureDisplayMirrorOfDisplay(cfg, d.id, source.id)
            }
        }
    }

    @discardableResult
    static func stopMirroring(_ all: [Display]) -> Bool {
        configure { cfg in
            for d in all where !d.blackedOut { CGConfigureDisplayMirrorOfDisplay(cfg, d.id, kCGNullDirectDisplay) }
        }
    }

    /// Make `d` the main display (menu bar and Dock) by moving it to the origin.
    @discardableResult
    static func setMain(_ d: Display, _ all: [Display]) -> Bool {
        let b = CGDisplayBounds(d.id)
        return configure { cfg in
            for o in active(all) {
                let ob = CGDisplayBounds(o.id)
                CGConfigureDisplayOrigin(cfg, o.id, Int32(ob.origin.x - b.origin.x), Int32(ob.origin.y - b.origin.y))
            }
        }
    }

    /// Swap the positions of two displays.
    @discardableResult
    static func swap(_ a: Display, _ b: Display) -> Bool {
        let ab = CGDisplayBounds(a.id), bb = CGDisplayBounds(b.id)
        return configure { cfg in
            CGConfigureDisplayOrigin(cfg, a.id, Int32(bb.origin.x), Int32(bb.origin.y))
            CGConfigureDisplayOrigin(cfg, b.id, Int32(ab.origin.x), Int32(ab.origin.y))
        }
    }

    /// Place displays left to right (or top to bottom), keeping the main display at the origin.
    @discardableResult
    static func line(_ ds: [Display], vertical: Bool) -> Bool {
        let list = active(ds)
        guard list.count > 1 else { return false }
        let sizes = list.map { CGDisplayBounds($0.id).size }
        let mainIdx = list.firstIndex { CGDisplayIsMain($0.id) != 0 } ?? 0
        var offsets: [CGFloat] = []
        var pos: CGFloat = 0
        for s in sizes { offsets.append(pos); pos += vertical ? s.height : s.width }
        let shift = offsets[mainIdx]
        return configure { cfg in
            for (i, d) in list.enumerated() {
                let o = offsets[i] - shift
                if vertical {
                    CGConfigureDisplayOrigin(cfg, d.id, Int32((sizes[mainIdx].width - sizes[i].width) / 2), Int32(o))
                } else {
                    CGConfigureDisplayOrigin(cfg, d.id, Int32(o), Int32(sizes[mainIdx].height - sizes[i].height))
                }
            }
        }
    }

    /// Two or more displays above one: the main display sits at the bottom center.
    @discardableResult
    static func above(_ ds: [Display]) -> Bool {
        let list = active(ds)
        guard list.count > 1, let main = list.first(where: { CGDisplayIsMain($0.id) != 0 }) ?? list.first else { return false }
        let top = list.filter { $0.id != main.id }
        let mb = CGDisplayBounds(main.id).size
        let totalW = top.reduce(CGFloat(0)) { $0 + CGDisplayBounds($1.id).width }
        var x = (mb.width - totalW) / 2
        return configure { cfg in
            CGConfigureDisplayOrigin(cfg, main.id, 0, 0)
            for d in top {
                let s = CGDisplayBounds(d.id).size
                CGConfigureDisplayOrigin(cfg, d.id, Int32(x), Int32(-s.height))
                x += s.width
            }
        }
    }
}

/// Night Mode: lower brightness and contrast and warm the colors. Turning it off restores the previous values.
final class NightMode {
    static let shared = NightMode()
    private(set) var on = false
    private var snapshot: [String: (Double, Double, Double, Double, Double)] = [:]

    func toggle() { set(!on) }

    func set(_ enable: Bool) {
        guard enable != on else { return }
        let ds = AppState.shared.displays.filter { !$0.blackedOut }
        if enable {
            for d in ds {
                let c = d.config
                snapshot[d.uuid] = (c.brightness, c.contrast, c.red, c.green, c.blue)
                d.setBrightness(min(c.brightness, 20), animated: true)
                if d.hasHardwareControls { d.setContrast(min(c.contrast, 40)) }
                d.setColor(red: 1, green: 0.82, blue: 0.62)
            }
        } else {
            for d in ds {
                guard let (b, c, r, g, bl) = snapshot[d.uuid] else { continue }
                d.setBrightness(b, animated: true)
                if d.hasHardwareControls { d.setContrast(c) }
                d.setColor(red: r, green: g, blue: bl)
            }
            snapshot = [:]
        }
        on = enable
        AppState.shared.objectWillChange.send()
        OSD.shared.showText(on ? "Night Mode on" : "Night Mode off", symbol: on ? "moon.stars.fill" : "sun.max")
    }
}

/// Cleaning Mode: black out every screen and ignore the keyboard so you can wipe the screens and keys.
/// Press Escape three times, or wait two minutes, to exit.
final class CleaningMode {
    static let shared = CleaningMode()
    private(set) var on = false
    private var windows: [NSWindow] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var escCount = 0
    private var timeout: DispatchWorkItem?

    func start() {
        guard !on else { return }
        guard Permissions.ensureAccessibility(forCleaning: true) else { return }
        on = true
        escCount = 0
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.backgroundColor = .black
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            w.ignoresMouseEvents = false
            let label = NSTextField(labelWithString: "Cleaning Mode. Press Esc three times to exit.")
            label.textColor = NSColor(white: 0.25, alpha: 1)
            label.font = .systemFont(ofSize: 14)
            label.sizeToFit()
            label.frame.origin = CGPoint(x: (screen.frame.width - label.frame.width) / 2, y: 40)
            w.contentView?.addSubview(label)
            w.orderFrontRegardless()
            windows.append(w)
        }
        NSCursor.hide()
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            | (1 << 14) // NX_SYSDEFINED: media keys
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(mask), callback: { _, type, event, _ in
                                    if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
                                        DispatchQueue.main.async { CleaningMode.shared.escape() }
                                    }
                                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput { return Unmanaged.passUnretained(event) }
                                    return nil
                                }, userInfo: nil)
        if let tap {
            source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: work)
    }

    private func escape() {
        escCount += 1
        if escCount >= 3 { stop() }
    }

    func stop() {
        guard on else { return }
        on = false
        timeout?.cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        NSCursor.unhide()
    }
}

enum Power {
    /// Put the Mac to sleep.
    static func sleepMac() {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }
}

/// "Keep this arrangement?" window with a countdown, like macOS shows after a resolution change.
final class ArrangementConfirm: ObservableObject {
    static let shared = ArrangementConfirm()
    @Published var secondsLeft = 15
    private var panel: NSPanel?
    private var timer: Timer?
    private var snapshot: Arrangement.Snapshot?

    func show(revertTo s: Arrangement.Snapshot) {
        // A second change while asking keeps the oldest layout as the one to go back to.
        if snapshot == nil { snapshot = s }
        secondsLeft = 15
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.secondsLeft -= 1
            if self.secondsLeft <= 0 { self.revert() }
        }
        if panel == nil {
            let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 340, height: 150), styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.level = .floating
            p.isMovableByWindowBackground = true
            let host = NSHostingView(rootView: ArrangementConfirmView(model: self))
            p.contentView = host
            p.setContentSize(host.fittingSize)
            panel = p
        }
        // Center on the main display, which always has the menu bar.
        if let screen = NSScreen.screens.first, let p = panel {
            p.setFrameOrigin(CGPoint(x: screen.frame.midX - p.frame.width / 2, y: screen.frame.midY - p.frame.height / 2))
        }
        panel?.orderFrontRegardless()
    }

    func keep() { close() }

    func revert() {
        if let s = snapshot { Arrangement.restore(s) }
        close()
    }

    private func close() {
        timer?.invalidate()
        timer = nil
        snapshot = nil
        panel?.orderOut(nil)
    }
}

struct ArrangementConfirmView: View {
    @ObservedObject var model: ArrangementConfirm

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.3.group").font(.system(size: 20)).foregroundStyle(.blue)
                Text("Keep this screen arrangement?").font(.system(size: 14, weight: .semibold))
            }
            Text("Your screens go back to the old arrangement in \(model.secondsLeft) seconds unless you click Keep.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Go back") { model.revert() }
                Button("Keep") { model.keep() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 14)
        .frame(width: 340)
    }
}
