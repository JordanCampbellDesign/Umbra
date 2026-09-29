import AppKit
import Foundation

enum ControlMethod: String, Codable, CaseIterable, Identifiable {
    case auto, appleNative, ddc, network, gamma
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Automatic"
        case .appleNative: return "Apple Native"
        case .ddc: return "DDC"
        case .network: return "Network"
        case .gamma: return "Gamma (software)"
        }
    }
}

/// Light or dark look for Umbra's own windows. "Match macOS" follows System Settings > Appearance.
enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match macOS"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum AdaptiveMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual, sync, location, clock, sensor
    var id: String { rawValue }
    var label: String {
        switch self {
        case .manual: return "Manual"
        case .sync: return "Sync"
        case .location: return "Location"
        case .clock: return "Clock"
        case .sensor: return "Sensor"
        }
    }
    var symbol: String {
        switch self {
        case .manual: return "hand.point.up.left"
        case .sync: return "arrow.triangle.2.circlepath"
        case .location: return "sun.max"
        case .clock: return "clock"
        case .sensor: return "sensor"
        }
    }
}

enum BlackOutMethod: String, Codable, CaseIterable, Identifiable {
    case disconnect, soft, ddcPower
    var id: String { rawValue }
    var label: String {
        switch self {
        case .disconnect: return "Disconnect display (frees GPU, keeps USB and charging)"
        case .soft: return "Mirror and dim to black"
        case .ddcPower: return "DDC power off (monitor standby)"
        }
    }
}

/// Settings stored per display, keyed by the display UUID.
struct DisplayConfig: Codable, Equatable {
    var method: ControlMethod = .auto
    var brightness: Double = 50
    var contrast: Double = 50
    var volume: Double = 50
    var muted = false
    var minBrightness: Double = 0
    var maxBrightness: Double = 100
    var minContrast: Double = 0
    var maxContrast: Double = 100
    var adaptive = true
    var syncOffset: Double = 0
    var networkURL = ""
    var subzero: Double = 0 // 0 = off, 1 = fully black
    var xdr = false
    var xdrLevel: Double = 1 // 0..1 of available headroom
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1
    var hotkeyInputs: [UInt16] = []
    /// Read values back from the monitor. Off by default because many monitors answer reads with noise.
    var readDDC = false
    /// Last input picked in Umbra. Shown when the monitor cannot report its input.
    var lastInput: UInt16?
    /// The monitor's maximum DDC value for brightness, contrast, and volume. 0 means detect it.
    var ddcMax: Int = 0
    /// The person's answer to "Did this screen change?" for a monitor that can't report its brightness. nil = not asked.
    var ddcWritesWork: Bool?
}

enum ScheduleAnchor: String, Codable, CaseIterable, Identifiable {
    case time, sunrise, noon, sunset
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct ScheduleItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var enabled = true
    var anchor: ScheduleAnchor = .time
    var hour = 8
    var minute = 0
    var offsetMinutes = 0
    var brightness: Double = 70
    var contrast: Double = 60
}

struct Preset: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// display UUID -> (brightness, contrast)
    var values: [String: [Double]]
}

struct AppPreset: Codable, Identifiable, Equatable {
    var id = UUID()
    var bundleID: String
    var name: String
    var brightness: Double = 100
    var contrast: Double = 70
}

enum HotkeyAction: String, Codable, CaseIterable, Identifiable {
    case brightnessUp, brightnessDown, contrastUp, contrastDown, volumeUp, volumeDown, mute
    case percent0, percent25, percent50, percent75, percent100
    case blackOut, blackOutNoMirroring, blackOutPowerOff, blackOutOthers, blackOutRestore
    case faceLight, nightMode, cleaningMode, xdr, cycleInput, cycleMode, togglePopover

    var id: String { rawValue }
    var label: String {
        switch self {
        case .brightnessUp: return "Brightness up (all displays)"
        case .brightnessDown: return "Brightness down (all displays)"
        case .contrastUp: return "Contrast up"
        case .contrastDown: return "Contrast down"
        case .volumeUp: return "Monitor volume up"
        case .volumeDown: return "Monitor volume down"
        case .mute: return "Monitor mute"
        case .percent0: return "Brightness 0%"
        case .percent25: return "Brightness 25%"
        case .percent50: return "Brightness 50%"
        case .percent75: return "Brightness 75%"
        case .percent100: return "Brightness 100%"
        case .blackOut: return "BlackOut display under cursor"
        case .blackOutNoMirroring: return "BlackOut display under cursor (without mirroring)"
        case .blackOutPowerOff: return "Power off display under cursor (DDC standby)"
        case .blackOutOthers: return "BlackOut all other displays"
        case .blackOutRestore: return "Turn all displays back on"
        case .faceLight: return "FaceLight"
        case .nightMode: return "Night Mode"
        case .cleaningMode: return "Cleaning Mode"
        case .xdr: return "XDR Brightness"
        case .cycleInput: return "Next input (display under cursor)"
        case .cycleMode: return "Next adaptive mode"
        case .togglePopover: return "Open menu"
        }
    }
}

struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifier mask
}

enum KeysTarget: String, Codable, CaseIterable, Identifiable {
    case cursor, all, main
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cursor: return "Display under the cursor"
        case .all: return "All displays"
        case .main: return "Main display"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var mode: AdaptiveMode = .manual
    var syncSource: String = "" // display UUID, empty = built-in
    var latitude: Double = 0
    var longitude: Double = 0
    var hasLocation = false
    var schedule: [ScheduleItem] = [
        ScheduleItem(anchor: .sunrise, hour: 0, minute: 0, brightness: 60, contrast: 55),
        ScheduleItem(anchor: .noon, hour: 0, minute: 0, brightness: 100, contrast: 70),
        ScheduleItem(anchor: .sunset, hour: 0, minute: 0, offsetMinutes: -30, brightness: 60, contrast: 55),
        ScheduleItem(anchor: .time, hour: 22, minute: 0, brightness: 20, contrast: 45),
    ]
    var smoothClock = true
    var sensorURL = ""
    /// True after the user entered a sensor address in the Sensor explainer or Settings.
    var sensorConfirmed = false
    var sensorMaxLux: Double = 2000
    var brightnessStep: Double = 6.25
    var keysTarget: KeysTarget = .cursor
    var mediaKeys = true
    var volumeKeys = true
    var subzeroEnabled = true
    var showOSD = true
    var smoothTransitions = true
    var blackOutMethod: BlackOutMethod = .disconnect
    var autoBlackOut = false
    var syncPollSeconds: Double = 0.5
    var faceLightBrightness: Double = 100
    var faceLightWarmth: Double = 0.6
    var presets: [Preset] = []
    var appPresets: [AppPreset] = []
    var hotkeys: [String: KeyCombo] = Hotkeys.defaults
    /// Bumped when the default hotkeys change, so old saved sets get the new defaults once.
    var hotkeysVersion = 0
    var blackedOut: [UInt32] = []
    var menuIcon = "sun.max.fill"
    var showDockIcon = false
    var appearance: AppAppearance = .system
    var scrollOnIcon = true
    /// Adaptive mode per desk setup, keyed by the set of connected external monitors.
    var deskModes: [String: AdaptiveMode] = [:]
    var rememberDeskModes = true
    var contrastFollowsBrightness = false
    // Away mode
    var awayEnabled = false
    var awayMinutes = 5
    var awayKeepAwake = true
    var awayKeepScreen = ""        // display uuid to leave on (dimmed), or empty
    var awayRespectVideo = true
    var awayDDCStandby = false
    var diagnosticsEnabled = false
    var followContrastMin: Double = 45
    var followContrastMax: Double = 75
    var scrollWithModifiers = true
    var openWindowAtLaunch = false
}

/// Small JSON-in-UserDefaults store.
enum Store {
    static let defaults = UserDefaults.standard

    static func load<T: Decodable>(_ key: String, _ type: T.Type) -> T? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    /// Set by `umbra render` in demo mode, so screenshots never change the person's real settings.
    static var readOnly = false

    static func save<T: Encodable>(_ key: String, _ value: T) {
        guard !readOnly else { return }
        if let d = try? JSONEncoder().encode(value) { defaults.set(d, forKey: key) }
    }
}

extension Store {
    /// Load a value and fill in any fields added since it was saved, using `fallback` as the base.
    static func loadMerged<T: Codable>(_ key: String, fallback: T) -> T {
        guard let stored = defaults.data(forKey: key),
              let storedObj = try? JSONSerialization.jsonObject(with: stored) as? [String: Any],
              let baseData = try? JSONEncoder().encode(fallback),
              var base = try? JSONSerialization.jsonObject(with: baseData) as? [String: Any]
        else { return fallback }
        base.merge(storedObj) { _, new in new }
        guard let merged = try? JSONSerialization.data(withJSONObject: base),
              let value = try? JSONDecoder().decode(T.self, from: merged) else { return fallback }
        return value
    }
}
