import AppKit
import CoreGraphics
import MetalKit
import QuartzCore

/// Owns every gamma table change so features that dim or tint (software brightness,
/// sub-zero, color gains, soft BlackOut) combine instead of fighting.
final class GammaController {
    static let shared = GammaController()

    struct State: Equatable {
        var factor: Double = 1 // overall multiplier 0..1
        var red: Double = 1, green: Double = 1, blue: Double = 1
        var isIdentity: Bool { factor >= 0.999 && red >= 0.999 && green >= 0.999 && blue >= 0.999 }
    }

    private var originals: [CGDirectDisplayID: ([CGGammaValue], [CGGammaValue], [CGGammaValue])] = [:]
    private var states: [CGDirectDisplayID: State] = [:]

    private func original(_ id: CGDirectDisplayID) -> ([CGGammaValue], [CGGammaValue], [CGGammaValue]) {
        if let o = originals[id] { return o }
        let cap = CGDisplayGammaTableCapacity(id)
        let n = Int(cap > 0 ? cap : 256)
        var r = [CGGammaValue](repeating: 0, count: n), g = r, b = r
        var count: UInt32 = 0
        if CGGetDisplayTransferByTable(id, UInt32(n), &r, &g, &b, &count) == .success, count > 0 {
            r = Array(r.prefix(Int(count))); g = Array(g.prefix(Int(count))); b = Array(b.prefix(Int(count)))
        } else {
            for i in 0 ..< n { let v = CGGammaValue(Double(i) / Double(n - 1)); r[i] = v; g[i] = v; b[i] = v }
        }
        let o = (r, g, b)
        // Do not store a table we dimmed ourselves.
        if states[id]?.isIdentity ?? true { originals[id] = o }
        return o
    }

    func set(_ id: CGDirectDisplayID, _ state: State) {
        if states[id] == state { return }
        if state.isIdentity {
            states[id] = nil
            restoreAll()
            return
        }
        _ = original(id)
        states[id] = state
        apply(id)
    }

    func state(_ id: CGDirectDisplayID) -> State { states[id] ?? State() }

    private func apply(_ id: CGDirectDisplayID) {
        guard let s = states[id] else { return }
        let (r0, g0, b0) = original(id)
        let f = max(0, min(1, s.factor))
        let r = r0.map { $0 * CGGammaValue(f * s.red) }
        let g = g0.map { $0 * CGGammaValue(f * s.green) }
        let b = b0.map { $0 * CGGammaValue(f * s.blue) }
        CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b)
    }

    /// macOS resets gamma after sleep and reconfiguration. Call this to put our tables back.
    func reapply() {
        for id in states.keys { apply(id) }
    }

    func restoreAll() {
        CGDisplayRestoreColorSyncSettings()
        reapply()
    }

    func forget(_ id: CGDirectDisplayID) {
        originals[id] = nil
    }
}

// MARK: - XDR Brightness

/// Pushes XDR panels past the SDR brightness cap. A click-through EDR Metal layer with a
/// multiply blend makes WindowServer render the whole screen in extended range, scaled by `factor`.
final class XDROverlay {
    private var window: NSWindow?
    private var view: MTKView?
    private var renderer: XDRRenderer?
    let screenID: CGDirectDisplayID

    init(screenID: CGDirectDisplayID) { self.screenID = screenID }

    static func headroom(_ id: CGDirectDisplayID) -> CGFloat {
        guard let s = NSScreen.screens.first(where: { $0.displayID == id }) else { return 1 }
        return s.maximumPotentialExtendedDynamicRangeColorComponentValue
    }

    static func supports(_ id: CGDirectDisplayID) -> Bool { headroom(id) > 1.5 }

    func show(level: Double) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == screenID }),
              let device = MTLCreateSystemDefaultDevice() else { return }
        // Cap the boost near 1600 nits peak vs 500 nits SDR on current XDR panels.
        let maxFactor = min(Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue), 3.2)
        let factor = 1 + (maxFactor - 1) * max(0, min(1, level))

        if window == nil {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.sharingType = .none
            let v = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: device)
            v.colorPixelFormat = .rgba16Float
            v.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            v.layer?.isOpaque = false
            (v.layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
            v.layer?.compositingFilter = "multiply"
            v.preferredFramesPerSecond = 5
            let r = XDRRenderer(device: device)
            v.delegate = r
            w.contentView = v
            window = w
            view = v
            renderer = r
        }
        window?.setFrame(screen.frame, display: true)
        renderer?.factor = factor
        view?.clearColor = MTLClearColor(red: factor, green: factor, blue: factor, alpha: 1)
        view?.needsDisplay = true
        window?.orderFrontRegardless()
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
        view = nil
        renderer = nil
    }
}

private final class XDRRenderer: NSObject, MTKViewDelegate {
    let queue: MTLCommandQueue?
    var factor: Double = 1
    init(device: MTLDevice) { queue = device.makeCommandQueue() }
    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}
    func draw(in view: MTKView) {
        view.clearColor = MTLClearColor(red: factor, green: factor, blue: factor, alpha: 1)
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buf = queue?.makeCommandBuffer(), let enc = buf.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.endEncoding()
        buf.present(drawable)
        buf.commit()
    }
}

// MARK: - FaceLight

/// A warm white frame around the screen that lights your face in video calls.
final class FaceLightOverlay {
    private var windows: [NSWindow] = []

    var isVisible: Bool { !windows.isEmpty }

    func show(warmth: Double) {
        hide()
        let warm = NSColor(calibratedRed: 1, green: 1 - 0.12 * warmth, blue: 1 - 0.35 * warmth, alpha: 1)
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.level = .screenSaver
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            w.sharingType = .none
            let v = FrameView(frame: CGRect(origin: .zero, size: screen.frame.size))
            v.color = warm
            w.contentView = v
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }

    private final class FrameView: NSView {
        var color: NSColor = .white
        override func draw(_: NSRect) {
            let inset = min(bounds.width, bounds.height) * 0.16
            let hole = bounds.insetBy(dx: inset * 1.4, dy: inset)
            let path = NSBezierPath(rect: bounds)
            path.append(NSBezierPath(roundedRect: hole, xRadius: 28, yRadius: 28).reversed)
            color.setFill()
            path.fill()
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
