import AppKit
import SwiftUI

struct MenuView: View {
    @ObservedObject var state = AppState.shared
    var openSettings: () -> Void
    /// True when shown in the main window instead of the menu bar popover.
    var inWindow = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(state.displays) { d in DisplayCard(display: d) }
                    if state.displays.isEmpty { Text("No displays found").foregroundStyle(.secondary).padding() }
                }
                .padding(12)
            }
            .frame(maxHeight: inWindow ? .infinity : 560)
            Divider().opacity(0.4)
            footer
        }
        .frame(minWidth: 380, idealWidth: 420, maxWidth: inWindow ? .infinity : 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "sun.max.fill").foregroundStyle(.yellow)
                Text("Umbra").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: openSettings) { Image(systemName: "gearshape") }.buttonStyle(.borderless).help("Settings")
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("openSettings")
            }
            ModePicker(selection: state.settings.mode) { state.requestMode($0) }
            ModeStatus()
        }
        .padding(12)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { state.faceLightOn }, set: { _ in state.toggleFaceLight() })) {
                Label("FaceLight", systemImage: "person.crop.square")
            }.toggleStyle(.button)
            if state.displays.contains(where: \.supportsXDR) {
                Toggle(isOn: Binding(get: { state.displays.contains { $0.config.xdr } }, set: { _ in state.toggleXDR() })) {
                    Label("XDR", systemImage: "sun.max.trianglebadge.exclamationmark")
                }.toggleStyle(.button)
            }
            Menu {
                ForEach(state.settings.presets) { p in Button(p.name) { state.applyPreset(p) } }
                if !state.settings.presets.isEmpty { Divider() }
                Button("Save current as preset…") { promptPreset() }
            } label: { Label("Presets", systemImage: "slider.horizontal.3") }
                .menuStyle(.borderlessButton).fixedSize()
            Menu {
                Section("Light") {
                    Button(NightMode.shared.on ? "Turn Night Mode off" : "Night Mode") { NightMode.shared.toggle() }
                    Button("Cleaning Mode") { CleaningMode.shared.start() }
                }
                Section("Arrange screens") {
                    Button("Side by side") { Arrangement.line(state.displays, vertical: false) }
                    Button("Top to bottom") { Arrangement.line(state.displays, vertical: true) }
                    Button("Others above main") { Arrangement.above(state.displays) }
                    Menu("Set main display") {
                        ForEach(state.displays) { d in Button(d.name) { Arrangement.setMain(d, state.displays) } }
                    }
                    Menu("Mirror all screens to") {
                        ForEach(state.displays) { d in Button(d.name) { Arrangement.mirror(to: d, state.displays) } }
                    }
                    Button("Stop mirroring") { Arrangement.stopMirroring(state.displays) }
                }
                Section("Power") {
                    Button("Turn screens off now (Away)") { Away.shared.now() }
                    Button("Turn all displays back on") { state.perform(.blackOutRestore) }
                    Button("Sleep Mac") { Power.sleepMac() }
                }
                Section("Help") {
                    Button("Report a problem with a monitor…") { Diagnostics.shared.openProblemReport() }
                }
            } label: { Label("More", systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }.buttonStyle(.borderless).help("Quit Umbra")
                .accessibilityLabel("Quit Umbra")
        }
        .padding(10)
        .controlSize(.small)
    }

    private func promptPreset() {
        let a = NSAlert()
        a.messageText = "Save preset"
        a.informativeText = "Saves the brightness and contrast of every display."
        let f = NSTextField(frame: CGRect(x: 0, y: 0, width: 240, height: 24))
        f.placeholderString = "Preset name"
        a.accessoryView = f
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty { state.savePreset(named: f.stringValue) }
    }
}

struct ModeStatus: View {
    @ObservedObject var state = AppState.shared
    @State private var now = Date()
    let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        // The line keeps its place while its text swaps with a short blur when the mode changes.
        ZStack(alignment: .leading) {
            Text(text).font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("mode.status")
                .id(state.settings.mode)
                .transition(.blurSwap)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.umbra, value: state.settings.mode)
        .onReceive(timer) { now = $0 }
    }

    private var text: String {
        let s = state.settings
        if let p = state.activeAppPreset { return "App preset active: \(p.name)" }
        switch s.mode {
        case .manual: return "You control brightness with sliders and keys."
        case .sync:
            let src = Engine.shared.syncSource?.name ?? "no Apple display"
            return "Following \(src). Move a slider to set an offset."
        case .location:
            guard s.hasLocation else { return "Waiting for location. Set it in Settings › Modes." }
            let e = Sun.elevation(at: now, lat: s.latitude, lon: s.longitude)
            let b = Engine.shared.locationBrightness(at: now) ?? 0
            return String(format: "Sun at %.0f°, target %.0f%%", e, b)
        case .clock:
            guard let (b, c) = Engine.shared.clockValues(at: now) else { return "No schedule items apply yet." }
            return String(format: "Schedule target: brightness %.0f%%, contrast %.0f%%", b, c)
        case .sensor:
            let lux = Engine.shared.sensorLux
            if s.sensorURL.isEmpty { return "No sensor set up. Add its address in Settings > Modes." }
            return lux < 0 ? "Waiting for the sensor at \(s.sensorURL)" : String(format: "Sensor reads %.0f lux", lux)
        }
    }
}

struct DisplayCard: View {
    @ObservedObject var display: Display
    @ObservedObject var state = AppState.shared
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: display.isBuiltin ? "laptopcomputer" : "display").foregroundStyle(.secondary)
                Text(display.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(display.method.label).font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                Spacer()
                if state.settings.mode != .manual {
                    Toggle("Adaptive", isOn: $display.config.adaptive).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        .help("Let the \(state.settings.mode.label) mode change this display")
                }
                Button { state.setBlackOut(display, !display.blackedOut) } label: {
                    Image(systemName: display.blackedOut ? "power.circle.fill" : "power.circle")
                        .foregroundStyle(display.blackedOut ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                .help(display.blackedOut ? "Turn this display back on" : "BlackOut: turn this display off")
                .accessibilityLabel(display.blackedOut ? "Turn \(display.name) back on" : "Turn \(display.name) off")
            }

            Group {
            if display.blackedOut {
                Text("This display is off. Click the power button or press ⌃⌘7 to turn it back on.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                brightnessRow
                if display.supportsXDR { xdrRow }
                if display.hasHardwareControls {
                    SliderRow(symbol: "circle.lefthalf.filled", value: Binding(get: { display.config.contrast }, set: { display.setContrast($0) }), range: 0 ... 100)
                    HStack(spacing: 6) {
                        Button { display.setMuted(!display.config.muted) } label: {
                            Image(systemName: display.config.muted ? "speaker.slash.fill" : "speaker.wave.2.fill").frame(width: 18)
                        }.buttonStyle(.borderless)
                        .accessibilityLabel(display.config.muted ? "Unmute \(display.name)" : "Mute \(display.name)")
                        Slider(value: Binding(get: { display.config.volume }, set: { display.setVolume($0) }), in: 0 ... 100)
                            .accessibilityLabel("Volume")
                            .accessibilityValue("\(Int(display.config.volume)) percent")
                        Text("\(Int(display.config.volume))").font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing)
                    }
                    inputRow
                }
                DisclosureGroup(isExpanded: $expanded.animation(.umbra)) { more.transition(.blurSwap) } label: {
                    Text("Resolution, rotation, color, and limits").font(.caption).foregroundStyle(.secondary)
                }
            }
            }
            .transition(.blurSwap)
        }
        .animation(.umbra, value: display.blackedOut)
        .padding(12)
        .background(.background.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .opacity(display.blackedOut ? 0.7 : 1)
    }

    /// Brightness runs 0 to 100. Dimming below 0% has its own slider, shown once brightness reaches 0.
    private var brightnessRow: some View {
        VStack(spacing: 6) {
            SliderRow(symbol: "sun.max.fill", id: "brightness.\(display.name)", value: Binding(
                get: { display.config.brightness },
                set: { v in
                    if display.config.subzero > 0 { display.setSubzero(0) }
                    state.userSetBrightness(display, v)
                }), range: 0 ... 100, tint: .yellow)
            if state.settings.subzeroEnabled, display.config.brightness < 0.5 || display.config.subzero > 0 {
                SliderRow(symbol: "moon.fill", value: Binding(
                    get: { display.config.subzero * 100 },
                    set: { display.setSubzero($0 / 100) }), range: 0 ... 100, tint: .indigo)
                    .help("Dim below 0%. Drag right to make the screen darker than its lowest setting.")
                    .transition(.blurReveal)
            }
        }
        .animation(.umbra, value: display.config.brightness < 0.5 || display.config.subzero > 0)
    }

    private var xdrRow: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { display.config.xdr }, set: { display.setXDR($0) })) {
                Text("XDR").font(.system(size: 11, weight: .bold))
            }.toggleStyle(.button).controlSize(.small)
            ZStack(alignment: .leading) {
                if display.config.xdr {
                    HStack(spacing: 6) {
                        Slider(value: Binding(get: { display.config.xdrLevel }, set: { display.setXDRLevel($0) }), in: 0 ... 1).tint(.orange)
                            .accessibilityLabel("XDR brightness")
                            .accessibilityValue("\(Int(display.config.xdrLevel * 100)) percent")
                        Text("\(Int(display.config.xdrLevel * 100))%").font(.caption.monospacedDigit()).frame(width: 36, alignment: .trailing)
                    }
                    .transition(.blurSwap)
                } else {
                    Text("Go brighter than 100%").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .transition(.blurSwap)
                }
            }
            .animation(.umbra, value: display.config.xdr)
        }
        .help("XDR Brightness: go past the normal brightness limit (up to about 1600 nits)")
    }

    private var inputRow: some View {
        HStack {
            Image(systemName: "cable.connector").frame(width: 18).foregroundStyle(.secondary)
            Picker("Input", selection: Binding(get: { display.inputSource ?? 0 }, set: { display.setInput($0) })) {
                if display.inputSource == nil {
                    Text("Choose input").tag(UInt16(0))
                } else if InputSource(rawValue: display.inputSource ?? 0) == nil {
                    Text(String(format: "Input 0x%02X", display.inputSource ?? 0)).tag(display.inputSource ?? 0)
                }
                ForEach(InputSource.allCases) { i in Text(i.label).tag(i.rawValue) }
            }
            .labelsHidden()
            .controlSize(.small)
            .help("Switch the monitor's video input. Umbra remembers the last input you chose.")
        }
    }

    @ViewBuilder private var more: some View {
        VStack(alignment: .leading, spacing: 8) {
            let modes = display.modes
            if !modes.isEmpty {
                Picker("Resolution", selection: Binding(get: { display.currentMode ?? modes[0] }, set: { display.setMode($0) })) {
                    ForEach(modes) { m in Text(m.label).tag(m) }
                }.controlSize(.small)
            }
            if display.canRotate {
                Picker("Rotation", selection: Binding(get: { display.rotation }, set: { display.setRotation($0) })) {
                    ForEach([0, 90, 180, 270], id: \.self) { Text("\($0)°").tag($0) }
                }.pickerStyle(.segmented).controlSize(.small)
            }
            Text("Color (software)").font(.caption).foregroundStyle(.secondary)
            SliderRow(symbol: "r.circle", value: Binding(get: { display.config.red }, set: { display.setColor(red: $0) }), range: 0 ... 1, tint: .red, percent: true)
            SliderRow(symbol: "g.circle", value: Binding(get: { display.config.green }, set: { display.setColor(green: $0) }), range: 0 ... 1, tint: .green, percent: true)
            SliderRow(symbol: "b.circle", value: Binding(get: { display.config.blue }, set: { display.setColor(blue: $0) }), range: 0 ... 1, tint: .blue, percent: true)
            Text("Brightness limits").font(.caption).foregroundStyle(.secondary)
            SliderRow(symbol: "arrow.down.to.line", value: $display.config.minBrightness, range: 0 ... 99)
            SliderRow(symbol: "arrow.up.to.line", value: $display.config.maxBrightness, range: 1 ... 100)
            if state.settings.mode != .manual, display.config.syncOffset != 0 {
                HStack {
                    Text("Adaptive offset: \(Int(display.config.syncOffset))").font(.caption)
                    Spacer()
                    Button("Reset") { display.config.syncOffset = 0; Engine.shared.tick(force: true) }.controlSize(.mini)
                }
            }
        }
        .padding(.top, 4)
    }
}

struct SliderRow: View {
    /// Spoken names for each slider, keyed by its symbol.
    static let labels = ["sun.max.fill": "Brightness", "moon.fill": "Dim below 0%", "circle.lefthalf.filled": "Contrast",
                         "r.circle": "Red", "g.circle": "Green", "b.circle": "Blue",
                         "arrow.down.to.line": "Minimum brightness", "arrow.up.to.line": "Maximum brightness"]
    let symbol: String
    /// Accessibility identifier for UI tests.
    var id: String? = nil
    @Binding var value: Double
    let range: ClosedRange<Double>
    var tint: Color = .accentColor
    var percent = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(tint).accessibilityHidden(true)
            Slider(value: $value, in: range).tint(tint)
                .accessibilityIdentifier(id ?? "")
                .accessibilityLabel(Self.labels[symbol] ?? "")
                .accessibilityValue("\(Int(percent ? value * 100 : value.rounded())) percent")
            Text(percent ? "\(Int(value * 100))" : "\(Int(value.rounded()))")
                .font(.caption.monospacedDigit()).frame(width: 30, alignment: .trailing).accessibilityHidden(true)
        }
    }
}
