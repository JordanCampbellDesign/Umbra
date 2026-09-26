import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @AppStorage("settingsTab") private var tab = "general"

    var body: some View {
        TabView(selection: $tab) {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }.tag("general")
            ModesTab().tabItem { Label("Modes", systemImage: "sun.max") }.tag("modes")
            DisplaysTab().tabItem { Label("Displays", systemImage: "display.2") }.tag("displays")
            HotkeysTab().tabItem { Label("Hotkeys", systemImage: "keyboard") }.tag("hotkeys")
            PresetsTab().tabItem { Label("Presets", systemImage: "slider.horizontal.3") }.tag("presets")
            AboutTab().tabItem { Label("CLI & About", systemImage: "terminal") }.tag("about")
        }
        .frame(width: 640, height: 560)
        .padding(.top, 8)
    }
}

struct GeneralTab: View {
    @ObservedObject var state = AppState.shared
    @State private var trusted = MediaKeys.shared.trusted

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch Umbra at login", isOn: Binding(get: { state.launchAtLogin }, set: { state.launchAtLogin = $0 }))
                Toggle("Open the main window when Umbra starts", isOn: $state.settings.openWindowAtLaunch)
                Toggle("Always show Umbra in the Dock", isOn: $state.settings.showDockIcon)
                Text("If the menu bar icon is hidden (for example behind the notch), open Umbra again from Applications or Spotlight to see the main window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keyboard") {
                Toggle("Brightness keys control external monitors", isOn: $state.settings.mediaKeys)
                Toggle("Volume keys control monitor speakers when they are the sound output", isOn: $state.settings.volumeKeys)
                Picker("Brightness keys adjust", selection: $state.settings.keysTarget) {
                    ForEach(KeysTarget.allCases) { Text($0.label).tag($0) }
                }
                Stepper(value: $state.settings.brightnessStep, in: 1 ... 25, step: 0.25) {
                    Text("Step size: \(state.settings.brightnessStep, specifier: "%.2f")%  (hold ⌥⇧ for a quarter step)")
                }
                if !trusted {
                    HStack {
                        Text("Umbra needs Accessibility access to read the brightness and volume keys.").font(.caption)
                        Spacer()
                        Button("Grant access") { Permissions.ensureAccessibility() }
                    }
                }
            }
            Section("Brightness") {
                Toggle("Sub-zero dimming (go below 0% with keys and sliders)", isOn: $state.settings.subzeroEnabled)
                Toggle("Smooth transitions", isOn: $state.settings.smoothTransitions)
                Toggle("Show on-screen display", isOn: $state.settings.showOSD)
            }
            Section("BlackOut") {
                Picker("Turn displays off by", selection: $state.settings.blackOutMethod) {
                    ForEach(BlackOutMethod.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Auto BlackOut: turn off the built-in display while an external monitor is connected", isOn: $state.settings.autoBlackOut)
                Text("⌃⌘6 turns off the display under the cursor. ⌃⌘⇧6 turns every display back on. Umbra also turns displays back on when it quits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("FaceLight") {
                Slider(value: $state.settings.faceLightBrightness, in: 50 ... 100) { Text("Brightness") }
                Slider(value: $state.settings.faceLightWarmth, in: 0 ... 1) { Text("Warmth") }
            }
        }
        .formStyle(.grouped)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in trusted = MediaKeys.shared.trusted }
    }
}

struct ModesTab: View {
    @ObservedObject var state = AppState.shared

    var body: some View {
        Form {
            Section("Adaptive mode") {
                Picker("Mode", selection: Binding(get: { state.settings.mode }, set: { state.requestMode($0) })) {
                    ForEach(AdaptiveMode.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
            Section("Sync") {
                Picker("Follow", selection: $state.settings.syncSource) {
                    Text("Built-in display").tag("")
                    ForEach(state.displays.filter { $0.method == .appleNative }) { Text($0.name).tag($0.uuid) }
                }
                Stepper(value: $state.settings.syncPollSeconds, in: 0.2 ... 5, step: 0.1) {
                    Text("Check every \(state.settings.syncPollSeconds, specifier: "%.1f") s")
                }
            }
            Section("Location") {
                HStack {
                    TextField("Latitude", value: $state.settings.latitude, format: .number)
                    TextField("Longitude", value: $state.settings.longitude, format: .number)
                    Button("Use my location") { Permissions.prepareLocation { ok in if ok { Engine.shared.requestLocation() } } }
                }
                Toggle("Coordinates are set", isOn: $state.settings.hasLocation)
                if state.settings.hasLocation {
                    let t = Sun.times(on: Date(), lat: state.settings.latitude, lon: state.settings.longitude)
                    Text("Sunrise \(fmt(t.sunrise)) · Noon \(fmt(t.noon)) · Sunset \(fmt(t.sunset))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Clock schedule") {
                ForEach($state.settings.schedule) { $item in ScheduleRow(item: $item) }
                    .onDelete { state.settings.schedule.remove(atOffsets: $0) }
                HStack {
                    Button("Add schedule") { state.settings.schedule.append(ScheduleItem()) }
                    Button("Remove last") { if !state.settings.schedule.isEmpty { state.settings.schedule.removeLast() } }
                    Spacer()
                    Toggle("Smooth transition between items", isOn: $state.settings.smoothClock)
                }
            }
            Section("Sensor") {
                TextField("Sensor address", text: $state.settings.sensorURL, prompt: Text("http://umbra-sensor.local/lux"))
                Text("A light sensor on your Wi-Fi that answers with the light level in lux. Umbra asks it every 2 seconds while Sensor mode is on. macOS asks for Local Network access the first time.")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $state.settings.sensorMaxLux, in: 100 ... 20000) {
                    Text("Full brightness at \(Int(state.settings.sensorMaxLux)) lux")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var help: String {
        switch state.settings.mode {
        case .manual: return "Nothing changes on its own."
        case .sync: return "External monitors follow the built-in display, which follows the Mac's light sensor."
        case .location: return "Brightness follows the height of the sun where you are."
        case .clock: return "Brightness and contrast follow the schedule below."
        case .sensor: return "Brightness follows an external light sensor on your network."
        }
    }

    private func fmt(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(date: .omitted, time: .shortened)
    }
}

struct ScheduleRow: View {
    @Binding var item: ScheduleItem

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $item.enabled).labelsHidden()
            Picker("", selection: $item.anchor) { ForEach(ScheduleAnchor.allCases) { Text($0.label).tag($0) } }
                .labelsHidden().frame(width: 90)
            if item.anchor == .time {
                Stepper("\(String(format: "%02d:%02d", item.hour, item.minute))", onIncrement: { bump(15) }, onDecrement: { bump(-15) })
                    .frame(width: 90)
            } else {
                Stepper("\(item.offsetMinutes >= 0 ? "+" : "")\(item.offsetMinutes)m", value: $item.offsetMinutes, in: -240 ... 240, step: 15)
                    .frame(width: 90)
            }
            Image(systemName: "sun.max").foregroundStyle(.yellow)
            Slider(value: $item.brightness, in: 0 ... 100)
            Text("\(Int(item.brightness))").monospacedDigit().frame(width: 26)
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.teal)
            Slider(value: $item.contrast, in: 0 ... 100).frame(width: 70)
        }
    }

    private func bump(_ m: Int) {
        let total = ((item.hour * 60 + item.minute + m) % 1440 + 1440) % 1440
        item.hour = total / 60
        item.minute = total % 60
    }
}

struct DisplaysTab: View {
    @ObservedObject var state = AppState.shared
    @State private var selected: String?

    var body: some View {
        HSplitView {
            List(state.displays, selection: $selected) { d in
                Label(d.name, systemImage: d.isBuiltin ? "laptopcomputer" : "display").tag(d.uuid)
            }
            .frame(minWidth: 170, maxWidth: 200)
            if let d = state.displays.first(where: { $0.uuid == selected }) ?? state.displays.first {
                DisplayDetail(display: d).frame(maxWidth: .infinity)
            }
        }
    }
}

struct DisplayDetail: View {
    @ObservedObject var display: Display

    var body: some View {
        Form {
            Section("Info") {
                LabeledContent("Name", value: display.name)
                LabeledContent("ID", value: "\(display.id)")
                LabeledContent("Control", value: display.method.label)
                LabeledContent("DDC link", value: display.link == nil ? "None" : (display.ddcResponsive == true ? "Found, reads work" : "Found"))
                LabeledContent("XDR capable", value: display.supportsXDR ? "Yes" : "No")
            }
            Section("Control method") {
                Picker("Method", selection: $display.config.method) {
                    ForEach(ControlMethod.allCases) { Text($0.label).tag($0) }
                }
                TextField("Network relay URL (for example http://raspberrypi.local:3485/1)", text: $display.config.networkURL)
                Text("Gamma dims in software. Set the monitor's own brightness to the maximum first. Network sends DDC commands to a relay such as a Raspberry Pi.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Read values from monitor at startup", isOn: $display.config.readDDC)
                Button("Read values from monitor now") { display.readHardware(force: true) }.disabled(display.link == nil)
            }
            Section("Limits") {
                Slider(value: $display.config.minBrightness, in: 0 ... 99) { Text("Min brightness \(Int(display.config.minBrightness))") }
                Slider(value: $display.config.maxBrightness, in: 1 ... 100) { Text("Max brightness \(Int(display.config.maxBrightness))") }
                Slider(value: $display.config.minContrast, in: 0 ... 99) { Text("Min contrast \(Int(display.config.minContrast))") }
                Slider(value: $display.config.maxContrast, in: 1 ... 100) { Text("Max contrast \(Int(display.config.maxContrast))") }
            }
            Section("Adaptive") {
                Toggle("Adaptive modes change this display", isOn: $display.config.adaptive)
                Slider(value: $display.config.syncOffset, in: -100 ... 100) { Text("Offset \(Int(display.config.syncOffset))") }
            }
            Section("Input hotkey cycle") {
                Text("⌃⌥⌘I switches between the inputs you check here.").font(.caption).foregroundStyle(.secondary)
                ForEach(InputSource.allCases) { i in
                    Toggle(i.label, isOn: Binding(
                        get: { display.config.hotkeyInputs.contains(i.rawValue) },
                        set: { on in
                            display.config.hotkeyInputs.removeAll { $0 == i.rawValue }
                            if on { display.config.hotkeyInputs.append(i.rawValue) }
                        }))
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: display.config.method) { _ in display.applyAll() }
    }
}

struct HotkeysTab: View {
    @ObservedObject var state = AppState.shared
    @State private var recording: HotkeyAction?
    @State private var monitor: Any?

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { a in
                    HStack {
                        Text(a.label)
                        Spacer()
                        Button(recording == a ? "Press keys…" : Hotkeys.describe(state.settings.hotkeys[a.rawValue])) { record(a) }
                            .frame(minWidth: 110)
                        Button { state.settings.hotkeys[a.rawValue] = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                HStack {
                    Text("Click a shortcut, then press the new keys. Press Esc to cancel.").font(.caption)
                    Spacer()
                    Button("Restore defaults") { state.settings.hotkeys = Hotkeys.defaults }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func record(_ a: HotkeyAction) {
        recording = a
        HotkeyCenter.shared.unregister()
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            defer {
                recording = nil
                if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
                HotkeyCenter.shared.register(state.settings.hotkeys)
            }
            if e.keyCode == 53 { return nil }
            let mods = Hotkeys.carbonModifiers(e.modifierFlags)
            state.settings.hotkeys[a.rawValue] = KeyCombo(keyCode: UInt32(e.keyCode), modifiers: mods)
            return nil
        }
    }
}

struct PresetsTab: View {
    @ObservedObject var state = AppState.shared
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Presets") {
                ForEach(state.settings.presets) { p in
                    HStack {
                        Text(p.name)
                        Spacer()
                        Button("Apply") { state.applyPreset(p) }
                        Button { state.settings.presets.removeAll { $0.id == p.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("New preset name", text: $newName)
                    Button("Save current values") { state.savePreset(named: newName); newName = "" }.disabled(newName.isEmpty)
                }
                Text("Run a preset from Shortcuts or scripts with `umbra preset <name>` or the link umbra://preset/<name>.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App presets") {
                Text("Set brightness and contrast while an app is in front. Values go back when you switch away.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($state.settings.appPresets) { $p in
                    VStack(alignment: .leading) {
                        HStack {
                            Text(p.name).bold()
                            Text(p.bundleID).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button { state.settings.appPresets.removeAll { $0.id == p.id } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                        Slider(value: $p.brightness, in: 0 ... 100) { Text("Brightness \(Int(p.brightness))") }
                        Slider(value: $p.contrast, in: 0 ... 100) { Text("Contrast \(Int(p.contrast))") }
                    }
                }
                Button("Add app…") { pickApp() }
            }
        }
        .formStyle(.grouped)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url, let b = Bundle(url: url), let id = b.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        state.settings.appPresets.append(AppPreset(bundleID: id, name: name))
    }
}

struct AboutTab: View {
    @State private var installed = ""

    var body: some View {
        Form {
            Section("Welcome") {
                Button("Show the welcome screen again") { Onboarding.show() }
            }
            Section("Command line") {
                HStack {
                    Button("Install `umbra` command") { installed = CLI.install() }
                    if !installed.isEmpty { Text("Installed at \(installed)").font(.caption) }
                }
                ScrollView {
                    Text(CLI.usage).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 220)
            }
            Section("About") {
                Text("Umbra \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                Text("Free display control for macOS. Every feature is included. No license, no daily limits.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
