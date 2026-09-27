import AppKit
import CoreGraphics
import IOKit.pwr_mgt

/// Away mode: when there has been no mouse or keyboard input for a while, fade the screens down,
/// then turn them black, while the Mac stays awake so downloads, builds, and agents keep running.
/// Any input brings every screen back to where it was.
final class Away {
    static let shared = Away()

    enum Stage { case active, dimmed, off }
    private(set) var stage: Stage = .active
    private var timer: Timer?
    private var lastIdle: Double = 0
    private var assertion: IOPMAssertionID = 0
    private var saved: [String: (brightness: Double, subzero: Double)] = [:]

    private var settings: AppSettings { AppState.shared.settings }

    func start() { schedule(interval: 2) }

    private func schedule(interval: Double) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = interval * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Seconds since the last mouse, keyboard, or trackpad input in this login session.
    static var idleSeconds: Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    enum Action: Equatable { case none, dim, off, wake }

    /// What Away mode should do next. Pure, so it can be unit tested.
    static func decide(stage: Stage, idle: Double, lastIdle: Double, enabled: Bool, minutes: Int, displayHeldOn: Bool) -> Action {
        if stage != .active {
            // Idle time drops when there is new input: wake up.
            if idle < lastIdle - 0.3 || idle < 1 { return .wake }
            if stage == .dimmed, idle >= Double(minutes + 1) * 60 { return .off }
            return .none
        }
        guard enabled, idle >= Double(minutes) * 60, !displayHeldOn else { return .none }
        return .dim
    }

    private func tick() {
        let idle = Away.idleSeconds
        defer { lastIdle = idle }
        let s = settings
        // Only ask the power system about other apps when it could matter.
        let heldOn = stage == .active && s.awayEnabled && idle >= Double(s.awayMinutes) * 60 && s.awayRespectVideo && Away.otherAppKeepsDisplayOn()
        switch Away.decide(stage: stage, idle: idle, lastIdle: lastIdle, enabled: s.awayEnabled, minutes: s.awayMinutes, displayHeldOn: heldOn) {
        case .dim: dim()
        case .off: turnOff()
        case .wake: wake()
        case .none: break
        }
    }

    /// True when another app asked macOS to keep the display on, for example while playing video or presenting.
    static func otherAppKeepsDisplayOn() -> Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let dict = status?.takeRetainedValue() as? [String: Int] else { return false }
        return (dict[kIOPMAssertPreventUserIdleDisplaySleep as String] ?? 0) > 0
    }

    private var targets: [Display] {
        AppState.shared.displays.filter { !$0.blackedOut && $0.uuid != settings.awayKeepScreen }
    }

    private func dim() {
        guard stage == .active else { return }
        stage = .dimmed
        Engine.shared.paused = true
        holdAwake(true)
        schedule(interval: 0.25)
        for d in AppState.shared.displays where !d.blackedOut {
            saved[d.uuid] = (d.config.brightness, d.config.subzero)
        }
        for d in targets {
            d.setBrightness(0, animated: true)
            if settings.subzeroEnabled { d.setSubzero(0.6) }
        }
        // The screen you chose to keep on stays readable, just dimmer.
        if let keep = AppState.shared.displays.first(where: { $0.uuid == settings.awayKeepScreen }) {
            keep.setBrightness(min(keep.config.brightness, 25), animated: true)
        }
    }

    private func turnOff() {
        stage = .off
        for d in targets {
            d.awayBlack = true
            d.applyGamma()
            if settings.awayDDCStandby, d.hasHardwareControls { d.powerOff(true) }
        }
    }

    /// Turn the screens off right away (menu, CLI, or hotkey). Any input wakes them.
    func now() {
        lastIdle = 0
        if stage == .active { dim() }
        turnOff()
        // Ignore the click or key press that started this.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.lastIdle = Away.idleSeconds }
    }

    func wake() {
        guard stage != .active else { return }
        let wasOff = stage == .off
        stage = .active
        for d in AppState.shared.displays {
            if d.awayBlack { d.awayBlack = false; d.applyGamma() }
            if wasOff, settings.awayDDCStandby, d.hasHardwareControls { d.powerOff(false) }
            if let s = saved[d.uuid] {
                d.setSubzero(s.subzero)
                d.setBrightness(s.brightness, animated: true)
            }
        }
        saved = [:]
        holdAwake(false)
        Engine.shared.paused = false
        Engine.shared.tick(force: true)
        schedule(interval: 2)
    }

    /// Keep the Mac from idle-sleeping while the screens are dark, so work keeps running.
    private func holdAwake(_ on: Bool) {
        if on, settings.awayKeepAwake, assertion == 0 {
            IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep as CFString,
                                        IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                        "Umbra Away mode keeps the Mac awake while the screens are off" as CFString, &assertion)
        } else if !on, assertion != 0 {
            IOPMAssertionRelease(assertion)
            assertion = 0
        }
    }

    var statusText: String {
        switch stage {
        case .active: return "on"
        case .dimmed: return "dimmed"
        case .off: return "screens off"
        }
    }
}
