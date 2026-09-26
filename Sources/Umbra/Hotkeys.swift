import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreAudio

enum Hotkeys {
    static let hyper = UInt32(controlKey | optionKey | cmdKey)
    static let ctrlCmd = UInt32(controlKey | cmdKey)
    static let version = 3

    static let defaults: [String: KeyCombo] = [
        HotkeyAction.brightnessUp.rawValue: KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: hyper),
        HotkeyAction.brightnessDown.rawValue: KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: hyper),
        HotkeyAction.contrastUp.rawValue: KeyCombo(keyCode: UInt32(kVK_UpArrow), modifiers: hyper | UInt32(shiftKey)),
        HotkeyAction.contrastDown.rawValue: KeyCombo(keyCode: UInt32(kVK_DownArrow), modifiers: hyper | UInt32(shiftKey)),
        HotkeyAction.volumeUp.rawValue: KeyCombo(keyCode: UInt32(kVK_RightArrow), modifiers: hyper),
        HotkeyAction.volumeDown.rawValue: KeyCombo(keyCode: UInt32(kVK_LeftArrow), modifiers: hyper),
        HotkeyAction.mute.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_M), modifiers: hyper),
        // Same combos Lunar ships with: ⌃⌘0 to ⌃⌘4 for fixed levels, ⌃⌘6 variants for BlackOut, ⌃⌘5 for FaceLight.
        HotkeyAction.percent0.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_0), modifiers: ctrlCmd),
        HotkeyAction.percent25.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: ctrlCmd),
        HotkeyAction.percent50.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: ctrlCmd),
        HotkeyAction.percent75.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: ctrlCmd),
        HotkeyAction.percent100.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_4), modifiers: ctrlCmd),
        HotkeyAction.blackOut.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: ctrlCmd),
        HotkeyAction.blackOutNoMirroring.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: ctrlCmd | UInt32(shiftKey)),
        HotkeyAction.blackOutPowerOff.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: ctrlCmd | UInt32(optionKey)),
        HotkeyAction.blackOutOthers.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_6), modifiers: hyper | UInt32(shiftKey)),
        HotkeyAction.blackOutRestore.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_7), modifiers: ctrlCmd),
        HotkeyAction.faceLight.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_5), modifiers: ctrlCmd),
        HotkeyAction.nightMode.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_N), modifiers: hyper),
        HotkeyAction.xdr.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_X), modifiers: hyper),
        HotkeyAction.cycleInput.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_I), modifiers: hyper),
        HotkeyAction.cycleMode.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: hyper),
        HotkeyAction.togglePopover.rawValue: KeyCombo(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(optionKey | shiftKey | cmdKey)),
    ]

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    static func describe(_ c: KeyCombo?) -> String {
        guard let c else { return "None" }
        var s = ""
        if c.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if c.modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if c.modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if c.modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + keyName(c.keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Escape: "⎋", kVK_Delete: "⌫", kVK_Tab: "⇥",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
            kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19",
        ]
        if let s = special[Int(code)] { return s }
        guard let src = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return "#\(code)" }
        let layout = unsafeBitCast(ptr, to: CFData.self)
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var len = 0
        let bytes = CFDataGetBytePtr(layout)!
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { kl in
            _ = UCKeyTranslate(kl, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                               OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return len > 0 ? String(utf16CodeUnits: chars, count: len).uppercased() : "#\(code)"
    }
}

/// Registers Carbon global hotkeys for every action that has a combo.
final class HotkeyCenter {
    static let shared = HotkeyCenter()
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: HotkeyAction] = [:]
    private var handlerInstalled = false

    func register(_ map: [String: KeyCombo]) {
        unregister()
        installHandler()
        var n: UInt32 = 1
        for action in HotkeyAction.allCases {
            guard let c = map[action.rawValue] else { continue }
            var ref: EventHotKeyRef?
            let hkID = EventHotKeyID(signature: OSType(0x554D4252), id: n) // 'UMBR'
            if RegisterEventHotKey(c.keyCode, c.modifiers, hkID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
                actions[n] = action
            }
            n += 1
        }
    }

    func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actions.removeAll()
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hk)
            if let a = HotkeyCenter.shared.actions[hk.id] {
                DispatchQueue.main.async { AppState.shared.perform(a) }
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Captures the keyboard brightness and volume keys so they control external monitors.
final class MediaKeys {
    static let shared = MediaKeys()
    private var tap: CFMachPort?
    private var retry: Timer?

    var trusted: Bool { AXIsProcessTrusted() }

    func requestAccess() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    func start() {
        guard tap == nil else { return }
        guard trusted else {
            retry?.invalidate()
            retry = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] t in
                if self?.trusted == true { t.invalidate(); self?.start() }
            }
            return
        }
        let mask = CGEventMask(1 << 14) | CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: { _, type, event, _ in
                                            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                                                if let t = MediaKeys.shared.tap { CGEvent.tapEnable(tap: t, enable: true) }
                                                return Unmanaged.passUnretained(event)
                                            }
                                            return MediaKeys.shared.handle(type, event) ? nil : Unmanaged.passUnretained(event)
                                        }, userInfo: nil) else { return }
        tap = t
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let s = AppState.shared.settings
        var key: Int32 = -1
        var down = false
        let flags = event.flags

        if type == .keyDown {
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            // Apple Silicon keyboards can send brightness keys as key codes 144 and 145.
            if code == 144 { key = 2; down = true } else if code == 145 { key = 3; down = true } else { return false }
        } else if type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
            key = Int32((ns.data1 & 0xFFFF_0000) >> 16)
            down = ((ns.data1 & 0xFF00) >> 8) == 0xA
        } else {
            return false
        }

        let fine = flags.contains(.maskAlternate) && flags.contains(.maskShift)
        switch key {
        case 2, 3: // brightness up / down
            guard s.mediaKeys else { return false }
            if down {
                DispatchQueue.main.async {
                    AppState.shared.stepBrightness(up: key == 2, fine: fine, target: s.keysTarget)
                }
            }
            return true
        case 0, 1, 7: // volume up / down / mute
            guard s.volumeKeys, let d = AudioOutput.monitorForCurrentOutput() else { return false }
            if down {
                DispatchQueue.main.async {
                    if key == 7 { AppState.shared.toggleMute(d) } else { AppState.shared.stepVolume(d, up: key == 0, fine: fine) }
                }
            }
            return true
        default:
            return false
        }
    }
}

enum AudioOutput {
    static func defaultOutputName() -> String? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr else { return nil }
        var name: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        addr.mSelector = kAudioObjectPropertyName
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let n = name?.takeRetainedValue() else { return nil }
        return n as String
    }

    /// The DDC display whose speakers are the current macOS audio output, if any.
    static func monitorForCurrentOutput() -> Display? {
        guard let out = defaultOutputName()?.lowercased() else { return nil }
        return AppState.shared.displays.first {
            $0.hasHardwareControls && (out.contains($0.name.lowercased()) || $0.name.lowercased().contains(out))
        }
    }
}
