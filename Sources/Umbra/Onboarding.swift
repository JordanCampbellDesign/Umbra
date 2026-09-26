import AppKit
import SwiftUI

/// First-launch welcome: shows the detected screens with live sliders, suggests a mode, and offers the brightness keys.
enum Onboarding {
    static let doneKey = "onboardingDone"
    private static var window: NSWindow?

    static var needed: Bool { !UserDefaults.standard.bool(forKey: doneKey) }

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: OnboardingView { finish() }.background(VisualEffect().ignoresSafeArea()))
            w.contentView = host
            w.setContentSize(host.fittingSize)
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                UserDefaults.standard.set(true, forKey: doneKey)
                DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.updateActivationPolicy() }
            }
            window = w
        }
        AppState.shared.refreshDisplays()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    static func finish() {
        UserDefaults.standard.set(true, forKey: doneKey)
        window?.close()
    }

    /// The mode Umbra suggests for this set of screens, with the reason shown to the user.
    static func suggestion(_ displays: [Display]) -> (AdaptiveMode, String) {
        let hasBuiltin = displays.contains(where: \.isBuiltin)
        let externals = displays.filter { !$0.isBuiltin }
        if hasBuiltin, !externals.isEmpty {
            return (.sync, "Your external screens follow the built-in display, which already adjusts to room light. No permission needed.")
        }
        if externals.isEmpty {
            return (.manual, "You have only the built-in display, which macOS already adjusts. Use Umbra for XDR, FaceLight, and hotkeys.")
        }
        return (.clock, "Your Mac has no built-in light sensor, so a daily schedule dims your screens in the evening. You can edit the times in Settings.")
    }
}

struct OnboardingView: View {
    @ObservedObject var state = AppState.shared
    @State private var trusted = MediaKeys.shared.trusted
    let done: () -> Void
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let (suggested, reason) = Onboarding.suggestion(state.displays)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill").font(.system(size: 26)).foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Welcome to Umbra").font(.system(size: 20, weight: .semibold))
                    Text("Control the brightness, contrast, volume, and power of every screen.")
                        .font(.system(size: 12.5)).foregroundStyle(.secondary)
                }
            }

            section("Your screens", "Try a slider. The change happens on the real screen.") {
                VStack(spacing: 8) {
                    ForEach(state.displays) { d in ScreenRow(display: d) }
                    if state.displays.isEmpty { Text("No screens found.").foregroundStyle(.secondary) }
                }
            }

            section("How should brightness change?", nil) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach([AdaptiveMode.manual, .sync, .clock, .location]) { m in
                            ModeChoice(mode: m, selected: state.settings.mode == m, recommended: m == suggested) {
                                state.requestMode(m)
                            }
                        }
                    }
                    Text(state.settings.mode == suggested ? reason : modeHelp(state.settings.mode) + " Suggested: \(suggested.label).")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Brightness and volume keys", nil) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "keyboard")
                        .foregroundStyle(trusted ? .green : .secondary).frame(width: 18)
                    Text(trusted ? "Your keyboard's brightness and volume keys now control the screen under the pointer."
                         : "Let the keyboard's brightness and volume keys control external screens. Umbra needs Accessibility access for this.")
                        .font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !trusted { Button("Turn on…") { Permissions.ensureAccessibility() } }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "menubar.arrow.up.rectangle").foregroundStyle(.secondary).frame(width: 18)
                Text("Umbra lives in the menu bar (the sun icon). If you can't see it, open Umbra again from Applications to get the main window.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Skip") { done() }
                Spacer()
                Button("Done") { done() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24).padding(.top, 30).padding(.bottom, 18)
        .frame(width: 520)
        .onReceive(poll) { _ in trusted = MediaKeys.shared.trusted }
    }

    private func section<C: View>(_ title: String, _ caption: String?, @ViewBuilder _ body: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
            }
            body()
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func modeHelp(_ m: AdaptiveMode) -> String {
        switch m {
        case .manual: return "Nothing changes on its own. You use the sliders and keys."
        case .sync: return "External screens follow the built-in display's brightness."
        case .clock: return "Brightness follows a daily schedule. Edit the times in Settings > Modes."
        case .location: return "Brightness follows the sun where you are."
        case .sensor: return "Brightness follows a light sensor on your network."
        }
    }
}

private struct ScreenRow: View {
    @ObservedObject var display: Display

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display").foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(display.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                Text(controls).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 190, alignment: .leading)
            Image(systemName: "sun.min").font(.caption).foregroundStyle(.secondary)
            Slider(value: Binding(get: { display.config.brightness }, set: { AppState.shared.userSetBrightness(display, $0) }), in: 0 ... 100)
                .controlSize(.small).tint(.yellow)
            Text("\(Int(display.config.brightness.rounded()))").font(.caption.monospacedDigit()).frame(width: 26, alignment: .trailing)
        }
    }

    private var controls: String {
        switch display.method {
        case .appleNative: return display.supportsXDR ? "Brightness and XDR, through macOS" : "Brightness, through macOS"
        case .ddc: return "Brightness, contrast, volume, input"
        case .network: return "Controlled through a network relay"
        case .gamma, .auto: return "Software dimming only"
        }
    }
}

private struct ModeChoice: View {
    let mode: AdaptiveMode
    let selected: Bool
    let recommended: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: mode.symbol).font(.system(size: 16))
                Text(mode.label).font(.system(size: 12, weight: .medium))
                Text(recommended ? "Suggested" : " ").font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? Color.accentColor : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(recommended && !selected ? Color.accentColor.opacity(0.6) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
