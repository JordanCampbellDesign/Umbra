import AppIntents
import Foundation
import SwiftUI
import WidgetKit

// Control Center and menu bar controls. They run in a sandboxed extension, so each one only
// posts a named action to the Umbra app, which checks it against a fixed list before acting.

enum ControlAction: String, AppEnum {
    case nightMode, faceLight, brighter, dimmer, blackOut, allOn

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Umbra Action"
    static let caseDisplayRepresentations: [ControlAction: DisplayRepresentation] = [
        .nightMode: "Night Mode", .faceLight: "FaceLight", .brighter: "Brighter", .dimmer: "Dimmer",
        .blackOut: "BlackOut", .allOn: "All Screens On",
    ]
}

struct UmbraControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Umbra Action"
    static let isDiscoverable = false

    @Parameter(title: "Action") var action: ControlAction

    init() {}
    init(_ action: ControlAction) { self.action = action }

    func perform() async throws -> some IntentResult {
        // Sandboxed senders can't attach userInfo, so the action travels as the notification object.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("design.jordancampbell.umbra.control"), object: action.rawValue, userInfo: nil, deliverImmediately: true)
        return .result()
    }
}

/// One button control that sends `action` to Umbra.
private func umbraButton(_ kind: String, _ action: ControlAction, _ title: LocalizedStringResource, _ symbol: String) -> some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: kind) {
        ControlWidgetButton(action: UmbraControlIntent(action)) {
            Label(title, systemImage: symbol)
        }
    }
    .displayName(title)
}

struct NightModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        umbraButton("design.jordancampbell.umbra.night", .nightMode, "Night Mode", "moon.stars")
            .description("Dim the screens and warm the colors. Tap again to restore.")
    }
}

struct FaceLightControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        umbraButton("design.jordancampbell.umbra.facelight", .faceLight, "FaceLight", "person.crop.square")
            .description("Light your face for video calls.")
    }
}

struct BrighterControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        umbraButton("design.jordancampbell.umbra.brighter", .brighter, "Brighter", "sun.max")
            .description("Raise the brightness of the screen under the pointer.")
    }
}

struct DimmerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        umbraButton("design.jordancampbell.umbra.dimmer", .dimmer, "Dimmer", "sun.min")
            .description("Lower the brightness of the screen under the pointer.")
    }
}

struct BlackOutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        umbraButton("design.jordancampbell.umbra.blackout", .blackOut, "BlackOut", "power")
            .description("Turn off the screen under the pointer, or turn it back on.")
    }
}

struct AllOnControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        umbraButton("design.jordancampbell.umbra.allon", .allOn, "All Screens On", "display.2")
            .description("Turn every screen back on after BlackOut.")
    }
}

@main
struct UmbraControlsBundle: WidgetBundle {
    var body: some Widget {
        NightModeControl()
        FaceLightControl()
        BrighterControl()
        DimmerControl()
        BlackOutControl()
        AllOnControl()
    }
}
