import AppKit
import SwiftUI

final class OSD {
    static let shared = OSD()
    enum Kind { case brightness, contrast, volume }

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private let model = OSDModel()

    func show(for d: Display, kind: Kind) {
        guard AppState.shared.settings.showOSD else { return }
        switch kind {
        case .brightness:
            if d.config.xdr {
                model.set(symbol: "sun.max.trianglebadge.exclamationmark.fill", title: "\(d.name) · XDR", value: d.config.xdrLevel, tint: .orange)
            } else if d.config.subzero > 0 {
                model.set(symbol: "moon.fill", title: "\(d.name) · Sub-zero", value: 1 - d.config.subzero, tint: .indigo)
            } else {
                model.set(symbol: d.config.brightness < 50 ? "sun.min.fill" : "sun.max.fill", title: d.name, value: d.config.brightness / 100, tint: .yellow)
            }
        case .contrast:
            model.set(symbol: "circle.lefthalf.filled", title: "\(d.name) · Contrast", value: d.config.contrast / 100, tint: .teal)
        case .volume:
            let v = d.config.muted ? 0 : d.config.volume / 100
            model.set(symbol: d.config.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", title: "\(d.name) · Volume", value: v, tint: .blue)
        }
        present(on: NSScreen.screens.first { $0.displayID == d.id })
    }

    func showText(_ text: String, symbol: String) {
        guard AppState.shared.settings.showOSD else { return }
        model.set(symbol: symbol, title: text, value: nil, tint: .accentColor)
        present(on: NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main)
    }

    /// Text message on a specific display, kept up for `seconds`.
    func showText(_ text: String, symbol: String, on d: Display, seconds: Double) {
        model.set(symbol: symbol, title: text, value: nil, tint: .accentColor)
        present(on: NSScreen.screens.first { $0.displayID == d.id }, seconds: seconds)
    }

    private func present(on screen: NSScreen?, seconds: Double = 1.3) {
        guard let screen else { return }
        if panel == nil {
            let p = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 260, height: 86), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.level = .statusBar
            p.isOpaque = false
            p.backgroundColor = .clear
            p.ignoresMouseEvents = true
            p.hasShadow = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            p.contentView = NSHostingView(rootView: OSDView(model: model))
            panel = p
        }
        let f = screen.visibleFrame
        panel?.setFrameOrigin(CGPoint(x: f.midX - 130, y: f.minY + 80))
        panel?.alphaValue = 1
        panel?.orderFrontRegardless()
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self?.panel?.animator().alphaValue = 0
            } completionHandler: { self?.panel?.orderOut(nil) }
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }
}

final class OSDModel: ObservableObject {
    @Published var symbol = "sun.max.fill"
    @Published var title = ""
    @Published var value: Double?
    @Published var tint: Color = .yellow
    func set(symbol: String, title: String, value: Double?, tint: Color) {
        self.symbol = symbol; self.title = title; self.value = value; self.tint = tint
    }
}

struct OSDView: View {
    @ObservedObject var model: OSDModel
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: model.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(model.tint)
                Text(model.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer()
                if let v = model.value { Text("\(Int((v * 100).rounded()))%").font(.system(size: 12, weight: .medium).monospacedDigit()).foregroundStyle(.secondary) }
            }
            if let v = model.value {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(model.tint).frame(width: max(6, g.size.width * v))
                    }
                }.frame(height: 6)
            }
        }
        .padding(16)
        .frame(width: 260, height: 86)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
