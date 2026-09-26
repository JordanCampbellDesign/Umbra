import AppKit
import Combine
import CoreGraphics
import ServiceManagement

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var displays: [Display] = []
    @Published var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            Store.save("settings", settings)
            if settings.mode != oldValue.mode, settings.rememberDeskModes, let key = deskKey {
                settings.deskModes[key] = settings.mode
            }
            if settings.mode != oldValue.mode || settings.syncSource != oldValue.syncSource || settings.syncPollSeconds != oldValue.syncPollSeconds {
                Engine.shared.restart()
            }
            if settings.hotkeys != oldValue.hotkeys { HotkeyCenter.shared.register(settings.hotkeys) }
            if settings.autoBlackOut != oldValue.autoBlackOut { scheduleAutoBlackOut() }
            if settings.showDockIcon != oldValue.showDockIcon { (NSApp.delegate as? AppDelegate)?.updateActivationPolicy() }
            if settings.subzeroEnabled != oldValue.subzeroEnabled { displays.forEach { $0.applyGamma() } }
        }
    }
    @Published var faceLightOn = false
    @Published var activeAppPreset: AppPreset?

    private var links: [AVLink] = []
    private var faceLightSnapshot: [String: (Double, Double, Bool)] = [:]
    private var appSnapshot: [String: (Double, Double)] = [:]
    private let faceLight = FaceLightOverlay()
    private var autoBlackOutWork: DispatchWorkItem?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        AppInfo.migrateLegacyDefaults()
        settings = Store.loadMerged("settings", fallback: AppSettings())
        // Older builds polled a placeholder sensor address, which made macOS ask for Local Network access for no reason.
        if !settings.sensorConfirmed, settings.sensorURL == "http://umbra-sensor.local/lux" { settings.sensorURL = "" }
        if settings.hotkeysVersion < Hotkeys.version {
            settings.hotkeys = Hotkeys.defaults
            settings.hotkeysVersion = Hotkeys.version
        }
    }

    // MARK: Lifecycle

    func start() {
        CLIToken.ensure()
        restoreStaleBlackOuts()
        refreshDisplays()
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            if flags.contains(.beginConfigurationFlag) { return }
            DispatchQueue.main.async { AppState.shared.scheduleReconfigure() }
        }, nil)
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.links = []
            self?.refreshDisplays()
            GammaController.shared.reapply()
            self?.displays.forEach { $0.applyAll() }
            // Work out the adaptive target now and spring to it, so screens don't sit at the old level after wake.
            Engine.shared.tick(force: true)
        }
        // Nothing to adjust while the screens are asleep, so stop the adaptive timers until they wake.
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in Engine.shared.suspend() }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { _ in Engine.shared.restart() }
        ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.appActivated(app?.bundleIdentifier)
        }
        HotkeyCenter.shared.register(settings.hotkeys)
        MediaKeys.shared.start()
        Engine.shared.restart()
        DistributedNotificationCenter.default().addObserver(forName: CLI.notification, object: nil, queue: .main) { n in
            // Only the CLI knows the token, so other apps can't send commands.
            guard let args = n.userInfo?["args"] as? [String], let token = n.userInfo?["token"] as? String,
                  token == CLIToken.ensure() else { return }
            let out = CLI.runInApp(args)
            if let id = n.userInfo?["id"] as? String {
                DistributedNotificationCenter.default().postNotificationName(CLI.replyNotification, object: id, userInfo: ["out": out], deliverImmediately: true)
            }
        }
    }

    func shutdown() {
        for d in displays where d.blackedOut { setBlackOut(d, false) }
        displays.forEach { $0.setXDR(false) }
        faceLight.hide()
        CGDisplayRestoreColorSyncSettings()
    }

    private var reconfigureWork: DispatchWorkItem?

    func scheduleReconfigure() {
        reconfigureWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reconfigured() }
        reconfigureWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: w)
    }

    func reconfigured() {
        links = []
        refreshDisplays()
        GammaController.shared.restoreAll()
        displays.forEach { $0.applyGamma(); $0.applyXDR() }
        scheduleAutoBlackOut()
    }

    func refreshDisplays() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let online = Array(ids.prefix(Int(count))).filter { id in
            // Hide hardware-mirrored secondaries unless we mirrored them for soft BlackOut.
            CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay || displays.contains { $0.id == id && $0.blackedOut }
        }
        // Rescan DDC links when a display appears that we have not seen, so hot-plugged monitors get DDC.
        let hasNew = online.contains { id in !displays.contains { $0.id == id } }
        if links.isEmpty || hasNew { links = DDC.discoverLinks() }

        // Links already owned by current displays are not free for new ones.
        var used = Set<Int>()
        for d in displays {
            guard let l = d.link else { continue }
            let i = links.indices.first { !used.contains($0) && (links[$0] === l || (links[$0].vendor == l.vendor && links[$0].product == l.product && links[$0].serial == l.serial)) }
            if let i { used.insert(i) }
        }

        var result: [Display] = []
        for id in online {
            if let existing = displays.first(where: { $0.id == id }) { result.append(existing); continue }
            var link: AVLink?
            if CGDisplayIsBuiltin(id) == 0, !Private.canChangeBrightness(id), let i = DDC.match(id, links: links, used: used) {
                used.insert(i)
                link = links[i]
            }
            let d = Display(id: id, link: link)
            d.readHardware()
            result.append(d)
        }
        // Keep disconnected BlackOut displays so the user can turn them back on.
        for d in displays where d.blackedOut && !result.contains(where: { $0.id == d.id }) { result.append(d) }
        result.sort { ($0.isBuiltin ? 0 : 1, $0.id) < ($1.isBuiltin ? 0 : 1, $1.id) }
        displays = result
        applyDeskSetup()
        cancellables = []
        for d in displays {
            d.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }
    }

    // MARK: Desk setups

    /// The set of connected external monitors, for example your home desk or your office desk.
    var deskKey: String? {
        let ext = displays.filter { !$0.isBuiltin }.map(\.uuid).sorted()
        return ext.isEmpty ? nil : ext.joined(separator: "+")
    }

    private var lastDeskKey: String?

    /// When the monitors change, switch to the mode last used with this set of monitors.
    private func applyDeskSetup() {
        let key = deskKey
        defer { lastDeskKey = key }
        guard key != lastDeskKey, settings.rememberDeskModes, let key else { return }
        guard let mode = settings.deskModes[key] else { settings.deskModes[key] = settings.mode; return }
        guard mode != settings.mode else { return }
        settings.mode = mode
        OSD.shared.showText("\(mode.label) mode for this desk", symbol: mode.symbol)
    }

    // MARK: Targets

    func displayUnderCursor() -> Display? {
        let p = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) }
        return displays.first { $0.id == screen?.displayID } ?? displays.first
    }

    func targets(_ t: KeysTarget) -> [Display] {
        let active = displays.filter { !$0.blackedOut }
        switch t {
        case .all: return active
        case .cursor: return displayUnderCursor().map { [$0] } ?? []
        case .main: return active.filter { $0.id == CGMainDisplayID() }
        }
    }

    // MARK: Keys

    func stepBrightness(up: Bool, fine: Bool, target: KeysTarget) {
        let step = fine ? settings.brightnessStep / 4 : settings.brightnessStep
        for d in targets(target) {
            if up {
                if settings.subzeroEnabled, d.config.subzero > 0 {
                    d.setSubzero(d.config.subzero - step / 100)
                } else if d.config.brightness >= 100, d.supportsXDR {
                    if !d.config.xdr { d.config.xdrLevel = 0; d.setXDR(true) }
                    d.setXDRLevel(d.config.xdrLevel + step / 100)
                } else {
                    userSetBrightness(d, d.config.brightness + step)
                }
            } else {
                if d.config.xdr {
                    if d.config.xdrLevel <= 0.001 { d.setXDR(false) } else { d.setXDRLevel(d.config.xdrLevel - step / 100) }
                } else if d.config.brightness <= 0, settings.subzeroEnabled {
                    d.setSubzero(d.config.subzero + step / 100)
                } else {
                    userSetBrightness(d, d.config.brightness - step)
                }
            }
            OSD.shared.show(for: d, kind: .brightness)
        }
    }

    func stepContrast(up: Bool) {
        for d in targets(settings.keysTarget) where d.hasHardwareControls {
            d.setContrast(d.config.contrast + (up ? 1 : -1) * settings.brightnessStep)
            OSD.shared.show(for: d, kind: .contrast)
        }
    }

    func stepVolume(_ d: Display, up: Bool, fine: Bool) {
        let step = fine ? 1.5625 : 6.25
        d.setVolume(d.config.volume + (up ? step : -step))
        OSD.shared.show(for: d, kind: .volume)
    }

    func toggleMute(_ d: Display) {
        d.setMuted(!d.config.muted)
        OSD.shared.show(for: d, kind: .volume)
    }

    /// A manual brightness change from a slider or key: teach the adaptive engine the new offset.
    func userSetBrightness(_ d: Display, _ v: Double) {
        let v = max(0, min(100, v))
        d.setBrightness(v)
        Engine.shared.userAdjusted(d, brightness: v)
    }

    /// Change the adaptive mode from the UI. Modes that need a permission explain it first.
    func requestMode(_ m: AdaptiveMode) {
        guard m != settings.mode else { return }
        switch m {
        case .location:
            Permissions.prepareLocation { ok in if ok { self.settings.mode = .location } }
        case .sensor:
            Permissions.prepareSensor { next in if let next { self.settings.mode = next } }
        default:
            settings.mode = m
        }
    }

    func perform(_ a: HotkeyAction) {
        let volTarget = AudioOutput.monitorForCurrentOutput() ?? displayUnderCursor()
        switch a {
        case .brightnessUp: stepBrightness(up: true, fine: false, target: .all)
        case .brightnessDown: stepBrightness(up: false, fine: false, target: .all)
        case .contrastUp: stepContrast(up: true)
        case .contrastDown: stepContrast(up: false)
        case .volumeUp: if let d = volTarget, d.hasHardwareControls { stepVolume(d, up: true, fine: false) }
        case .volumeDown: if let d = volTarget, d.hasHardwareControls { stepVolume(d, up: false, fine: false) }
        case .mute: if let d = volTarget, d.hasHardwareControls { toggleMute(d) }
        case .percent0: setAll(0)
        case .percent25: setAll(25)
        case .percent50: setAll(50)
        case .percent75: setAll(75)
        case .percent100: setAll(100)
        case .blackOut: if let d = displayUnderCursor() { setBlackOut(d, !d.blackedOut) }
        case .blackOutNoMirroring: if let d = displayUnderCursor() { setBlackOut(d, !d.blackedOut, method: .disconnect) }
        case .blackOutPowerOff: if let d = displayUnderCursor() { setBlackOut(d, !d.blackedOut, method: .ddcPower) }
        case .blackOutOthers:
            let keep = displayUnderCursor()
            let others = displays.filter { $0.id != keep?.id }
            let turnOn = others.allSatisfy(\.blackedOut)
            others.forEach { setBlackOut($0, !turnOn) }
        case .blackOutRestore: displays.filter(\.blackedOut).forEach { setBlackOut($0, false) }
        case .faceLight: toggleFaceLight()
        case .nightMode: NightMode.shared.toggle()
        case .cleaningMode: CleaningMode.shared.start()
        case .xdr: toggleXDR()
        case .cycleInput: if let d = displayUnderCursor() { cycleInput(d) }
        case .cycleMode:
            let all = AdaptiveMode.allCases
            let i = all.firstIndex(of: settings.mode) ?? 0
            requestMode(all[(i + 1) % all.count])
            OSD.shared.showText(settings.mode.label + " mode", symbol: settings.mode.symbol)
        case .togglePopover: (NSApp.delegate as? AppDelegate)?.togglePopover()
        }
    }

    func setAll(_ v: Double) {
        for d in displays where !d.blackedOut {
            d.setSubzero(0)
            if d.config.xdr { d.setXDR(false) }
            userSetBrightness(d, v)
            OSD.shared.show(for: d, kind: .brightness)
        }
    }

    func cycleInput(_ d: Display) {
        guard d.hasHardwareControls else { return }
        let inputs = d.config.hotkeyInputs.isEmpty ? [InputSource.hdmi1.rawValue, InputSource.hdmi2.rawValue, InputSource.displayPort1.rawValue, InputSource.usbC1.rawValue] : d.config.hotkeyInputs
        let i = inputs.firstIndex(of: d.inputSource ?? 0) ?? -1
        let next = inputs[(i + 1) % inputs.count]
        d.setInput(next)
        OSD.shared.showText(InputSource(rawValue: next)?.label ?? "Input \(next)", symbol: "cable.connector")
    }

    // MARK: XDR

    func toggleXDR() {
        let capable = displays.filter(\.supportsXDR)
        guard !capable.isEmpty else { OSD.shared.showText("No XDR display", symbol: "sun.max.trianglebadge.exclamationmark"); return }
        let on = !capable.contains { $0.config.xdr }
        capable.forEach { $0.setXDR(on) }
        OSD.shared.showText(on ? "XDR Brightness on" : "XDR Brightness off", symbol: "sun.max.fill")
    }

    // MARK: FaceLight

    func toggleFaceLight() {
        if faceLightOn {
            faceLight.hide()
            for d in displays {
                if let (b, c, x) = faceLightSnapshot[d.uuid] {
                    d.setBrightness(b, animated: true)
                    if d.hasHardwareControls { d.setContrast(c) }
                    d.setXDR(x)
                }
            }
            faceLightSnapshot = [:]
            faceLightOn = false
        } else {
            for d in displays where !d.blackedOut {
                faceLightSnapshot[d.uuid] = (d.config.brightness, d.config.contrast, d.config.xdr)
                d.setBrightness(settings.faceLightBrightness, animated: true)
                if d.hasHardwareControls { d.setContrast(80) }
            }
            faceLight.show(warmth: settings.faceLightWarmth)
            faceLightOn = true
        }
        OSD.shared.showText(faceLightOn ? "FaceLight on" : "FaceLight off", symbol: "person.crop.square.filled.and.at.rectangle")
    }

    // MARK: BlackOut

    private var activeCount: Int { displays.filter { !$0.blackedOut }.count }

    @discardableResult
    func setBlackOut(_ d: Display, _ on: Bool, method: BlackOutMethod? = nil) -> Bool {
        guard d.blackedOut != on else { return true }
        let m = method ?? settings.blackOutMethod
        if on, activeCount <= 1, m != .ddcPower {
            OSD.shared.showText("Can't turn off the last display", symbol: "exclamationmark.triangle")
            return false
        }
        if on, d.config.xdr { d.setXDR(false) }
        var ok = true
        switch m {
        case .disconnect:
            ok = setEnabled(d.id, !on)
            if !ok { return setBlackOut(d, on, method: .soft) }
        case .soft:
            var cfg: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&cfg)
            let master = displays.first { $0.id != d.id && !$0.blackedOut }?.id ?? CGMainDisplayID()
            CGConfigureDisplayMirrorOfDisplay(cfg, d.id, on ? master : kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(cfg, .forSession)
            if d.method == .appleNative { Private.setBrightness(d.id, on ? 0 : Float(d.config.brightness / 100)) }
        case .ddcPower:
            d.powerOff(on)
        }
        d.blackedOut = on
        d.applyGamma()
        if !on { d.applyAll() }
        var saved = Set(settings.blackedOut)
        if on { saved.insert(d.id) } else { saved.remove(d.id) }
        settings.blackedOut = Array(saved)
        OSD.shared.showText(on ? "\(d.name) off" : "\(d.name) on", symbol: on ? "moon.fill" : "sun.max")
        return ok
    }

    private func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> Bool {
        guard let fn = Private.configureEnabled else { return false }
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success else { return false }
        let err = fn(cfg, id, enabled)
        guard err == .success else { CGCancelDisplayConfiguration(cfg); return false }
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }

    /// If the app quit or crashed with displays off, bring them back at launch.
    private func restoreStaleBlackOuts() {
        for id in settings.blackedOut {
            _ = setEnabled(id, true)
            var cfg: CGDisplayConfigRef?
            CGBeginDisplayConfiguration(&cfg)
            CGConfigureDisplayMirrorOfDisplay(cfg, id, kCGNullDirectDisplay)
            CGCompleteDisplayConfiguration(cfg, .forSession)
        }
        settings.blackedOut = []
    }

    // MARK: Auto BlackOut

    private func scheduleAutoBlackOut() {
        autoBlackOutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.runAutoBlackOut() }
        autoBlackOutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func runAutoBlackOut() {
        guard let builtin = displays.first(where: \.isBuiltin) else { return }
        let externals = displays.filter { !$0.isBuiltin && !$0.blackedOut && CGDisplayIsOnline($0.id) != 0 }
        if settings.autoBlackOut, !externals.isEmpty, !builtin.blackedOut {
            setBlackOut(builtin, true)
        } else if builtin.blackedOut, externals.isEmpty || !settings.autoBlackOut {
            setBlackOut(builtin, false)
        }
    }

    // MARK: Presets

    func savePreset(named name: String) {
        var values: [String: [Double]] = [:]
        for d in displays { values[d.uuid] = [d.config.brightness, d.config.contrast] }
        settings.presets.removeAll { $0.name == name }
        settings.presets.append(Preset(name: name, values: values))
    }

    func applyPreset(_ p: Preset) {
        for d in displays {
            guard let v = p.values[d.uuid], v.count == 2 else { continue }
            d.setBrightness(v[0], animated: true)
            if d.hasHardwareControls { d.setContrast(v[1]) }
        }
        OSD.shared.showText(p.name, symbol: "slider.horizontal.3")
    }

    func applyPreset(named name: String) -> Bool {
        guard let p = settings.presets.first(where: { $0.name.lowercased() == name.lowercased() }) else { return false }
        applyPreset(p)
        return true
    }

    // MARK: App presets

    private func appActivated(_ bundleID: String?) {
        let preset = settings.appPresets.first { $0.bundleID == bundleID }
        if let preset {
            if activeAppPreset == nil {
                for d in displays { appSnapshot[d.uuid] = (d.config.brightness, d.config.contrast) }
            }
            activeAppPreset = preset
            Engine.shared.paused = true
            for d in displays where !d.blackedOut {
                d.setBrightness(preset.brightness, animated: true)
                if d.hasHardwareControls { d.setContrast(preset.contrast) }
            }
        } else if activeAppPreset != nil {
            activeAppPreset = nil
            Engine.shared.paused = false
            for d in displays {
                guard let (b, c) = appSnapshot[d.uuid] else { continue }
                d.setBrightness(b, animated: true)
                if d.hasHardwareControls { d.setContrast(c) }
            }
            appSnapshot = [:]
            Engine.shared.tick(force: true)
        }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            catch { NSLog("Umbra login item: \(error)") }
            objectWillChange.send()
        }
    }
}
