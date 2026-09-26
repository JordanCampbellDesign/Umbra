#if canImport(AppIntents)
import AppIntents
import CoreGraphics

// Siri and Shortcuts actions. Each one runs inside the Umbra app and uses the same code as the menu.

// MARK: Displays as things Siri can name

/// Brand name from the EDID vendor code, so "my Samsung" matches a monitor named C27F390.
enum Brand {
    static let names: [String: String] = [
        "SAM": "Samsung", "GSM": "LG", "DEL": "Dell", "ACI": "Asus", "AUS": "Asus", "BNQ": "BenQ",
        "HWP": "HP", "LEN": "Lenovo", "APP": "Apple", "PHL": "Philips", "VSC": "ViewSonic", "AOC": "AOC",
        "MSI": "MSI", "GBT": "Gigabyte", "ACR": "Acer", "HPN": "HP", "SNY": "Sony", "EIZ": "Eizo",
    ]

    static func of(_ id: CGDirectDisplayID) -> String? {
        let v = CGDisplayVendorNumber(id)
        let letters = [(v >> 10) & 31, (v >> 5) & 31, v & 31].map { Character(UnicodeScalar(UInt8(64 + $0))) }
        return names[String(letters)]
    }
}

struct DisplayEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Display"
    static let defaultQuery = DisplayQuery()

    let id: String
    let name: String
    let brand: String?

    var displayRepresentation: DisplayRepresentation {
        if let brand, !name.localizedCaseInsensitiveContains(brand) {
            return DisplayRepresentation(title: "\(brand) \(name)")
        }
        return DisplayRepresentation(title: "\(name)")
    }

    /// Words a person might use for this display.
    var words: [String] {
        var w = [name.lowercased()]
        if let brand { w.append(brand.lowercased()) }
        if name == "Built-in Display" { w += ["built-in", "built in", "laptop", "macbook", "internal"] }
        return w
    }

    @MainActor init(_ d: Display) {
        id = d.uuid
        name = d.name
        brand = d.isBuiltin ? nil : Brand.of(d.id)
    }

    @MainActor var display: Display? { AppState.shared.displays.first { $0.uuid == id } }
}

struct DisplayQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [DisplayEntity] {
        AppState.shared.displays.filter { identifiers.contains($0.uuid) }.map(DisplayEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [DisplayEntity] {
        let q = string.lowercased().replacingOccurrences(of: "monitor", with: "").replacingOccurrences(of: "display", with: "")
            .replacingOccurrences(of: "screen", with: "").replacingOccurrences(of: "my ", with: "").trimmingCharacters(in: .whitespaces)
        let all = AppState.shared.displays.map(DisplayEntity.init)
        guard !q.isEmpty else { return all }
        return all.filter { e in e.words.contains { $0.contains(q) || q.contains($0) } }
    }

    @MainActor func suggestedEntities() async throws -> [DisplayEntity] {
        AppState.shared.displays.map(DisplayEntity.init)
    }
}

/// Displays to act on: the named one, or every display that is on.
@MainActor private func targets(_ e: DisplayEntity?) throws -> [Display] {
    AppState.shared.refreshDisplays()
    if let e {
        guard let d = e.display else { throw IntentError.displayGone(e.name) }
        return [d]
    }
    return AppState.shared.displays.filter { !$0.blackedOut }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case displayGone(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .displayGone(n): return "\(n) is not connected."
        }
    }
}

private func names(_ ds: [Display]) -> String {
    ds.count > 1 ? "all screens" : ds.first?.name ?? "the screen"
}

// MARK: Brightness

struct SetBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Brightness"
    static let description = IntentDescription("Set a display's brightness to a percent.")

    @Parameter(title: "Display", description: "Leave empty for all screens.") var display: DisplayEntity?
    @Parameter(title: "Brightness", inclusiveRange: (0, 100)) var level: Int

    static var parameterSummary: some ParameterSummary { Summary("Set brightness of \(\.$display) to \(\.$level)%") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ds = try targets(display)
        ds.forEach { AppState.shared.userSetBrightness($0, Double(level)) }
        return .result(dialog: "Set \(names(ds)) to \(level)%.")
    }
}

enum Direction: String, AppEnum {
    case up, down
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    static let caseDisplayRepresentations: [Direction: DisplayRepresentation] = [.up: "Raise", .down: "Lower"]
}

struct AdjustBrightnessIntent: AppIntent {
    static let title: LocalizedStringResource = "Raise or Lower Brightness"
    static let description = IntentDescription("Raise or lower brightness by a number of percent.")

    @Parameter(title: "Direction", default: .down) var direction: Direction
    @Parameter(title: "Amount", default: 10, inclusiveRange: (1, 100)) var amount: Int
    @Parameter(title: "Display", description: "Leave empty for all screens.") var display: DisplayEntity?

    static var parameterSummary: some ParameterSummary { Summary("\(\.$direction) brightness of \(\.$display) by \(\.$amount)%") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ds = try targets(display)
        let delta = Double(direction == .up ? amount : -amount)
        for d in ds { AppState.shared.userSetBrightness(d, max(0, min(100, d.config.brightness + delta))) }
        let now = ds.first.map { Int($0.config.brightness.rounded()) } ?? 0
        return .result(dialog: "\(direction == .up ? "Raised" : "Lowered") \(names(ds)) to \(now)%.")
    }
}

// MARK: Power

struct TurnDisplayOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Display Off"
    static let description = IntentDescription("Turn a display off with BlackOut. Its windows move to your other screens.")

    @Parameter(title: "Display") var display: DisplayEntity

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let d = try targets(display).first else { throw IntentError.displayGone(display.name) }
        let ok = AppState.shared.setBlackOut(d, true)
        return .result(dialog: ok ? "Turned off \(d.name)." : "Can't turn off \(d.name) because it's the last screen that's on.")
    }
}

struct TurnDisplayOnIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Display On"
    static let description = IntentDescription("Turn a display back on after BlackOut.")

    @Parameter(title: "Display", description: "Leave empty to turn every display back on.") var display: DisplayEntity?

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = AppState.shared
        let ds = display == nil ? s.displays.filter(\.blackedOut) : try targets(display)
        ds.forEach { s.setBlackOut($0, false) }
        return .result(dialog: ds.isEmpty ? "All screens are already on." : "Turned on \(names(ds)).")
    }
}

// MARK: Night Mode, FaceLight, modes

struct NightModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Night Mode"
    static let description = IntentDescription("Dim the screens, lower contrast, and warm the colors. Turning it off restores your values.")

    @Parameter(title: "On", default: true) var on: Bool

    static var parameterSummary: some ParameterSummary { Summary("Turn Night Mode \(\.$on)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        NightMode.shared.set(on)
        return .result(dialog: on ? "Night Mode is on." : "Night Mode is off.")
    }
}

struct FaceLightIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle FaceLight"
    static let description = IntentDescription("Light your face for video calls with a bright frame around the screens.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppState.shared.toggleFaceLight()
        return .result(dialog: AppState.shared.faceLightOn ? "FaceLight is on." : "FaceLight is off.")
    }
}

extension AdaptiveMode: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Adaptive Mode"
    static let caseDisplayRepresentations: [AdaptiveMode: DisplayRepresentation] = [
        .manual: "Manual", .sync: "Sync", .location: "Location", .clock: "Clock", .sensor: "Sensor",
    ]
}

struct SetModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Adaptive Mode"
    static let description = IntentDescription("Choose how brightness changes on its own.")

    @Parameter(title: "Mode") var mode: AdaptiveMode

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        AppState.shared.requestMode(mode)
        return .result(dialog: "Switched to \(mode.label) mode.")
    }
}

// MARK: Siri phrases

struct UmbraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TurnDisplayOffIntent(), phrases: [
            "Turn off \(\.$display) with \(.applicationName)",
            "Turn off my \(\.$display) in \(.applicationName)",
            "\(.applicationName) turn off \(\.$display)",
        ], shortTitle: "Turn Display Off", systemImageName: "power")
        AppShortcut(intent: TurnDisplayOnIntent(), phrases: [
            "Turn on \(\.$display) with \(.applicationName)",
            "Turn my screens back on with \(.applicationName)",
            "\(.applicationName) turn on \(\.$display)",
        ], shortTitle: "Turn Display On", systemImageName: "power.circle")
        AppShortcut(intent: AdjustBrightnessIntent(), phrases: [
            "Lower the brightness with \(.applicationName)",
            "Dim my screens with \(.applicationName)",
            "\(.applicationName) lower brightness",
            "Raise the brightness with \(.applicationName)",
            "\(.applicationName) raise brightness",
        ], shortTitle: "Raise or Lower Brightness", systemImageName: "sun.max")
        AppShortcut(intent: SetBrightnessIntent(), phrases: [
            "Set brightness with \(.applicationName)",
            "Set \(\.$display) brightness with \(.applicationName)",
        ], shortTitle: "Set Brightness", systemImageName: "sun.min")
        AppShortcut(intent: NightModeIntent(), phrases: [
            "Turn on Night Mode in \(.applicationName)",
            "\(.applicationName) night mode",
            "Start Night Mode with \(.applicationName)",
        ], shortTitle: "Night Mode", systemImageName: "moon.stars")
        AppShortcut(intent: FaceLightIntent(), phrases: [
            "Toggle FaceLight in \(.applicationName)",
            "\(.applicationName) face light",
        ], shortTitle: "FaceLight", systemImageName: "person.crop.square")
        AppShortcut(intent: SetModeIntent(), phrases: [
            "Switch \(.applicationName) to \(\.$mode) mode",
            "Set \(.applicationName) mode to \(\.$mode)",
        ], shortTitle: "Set Adaptive Mode", systemImageName: "arrow.triangle.2.circlepath")
    }
}
#endif
