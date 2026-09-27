import XCTest
@testable import Umbra

final class AwayTests: XCTestCase {
    func decide(_ stage: Away.Stage, idle: Double, last: Double = 0, enabled: Bool = true, minutes: Int = 5, held: Bool = false) -> Away.Action {
        Away.decide(stage: stage, idle: idle, lastIdle: last, enabled: enabled, minutes: minutes, displayHeldOn: held)
    }

    func testDoesNothingWhileYouAreWorking() {
        XCTAssertEqual(decide(.active, idle: 30), .none)
        XCTAssertEqual(decide(.active, idle: 299), .none)
    }

    func testDimsAfterTheDelay() {
        XCTAssertEqual(decide(.active, idle: 300), .dim)
    }

    func testStaysOffWhenDisabled() {
        XCTAssertEqual(decide(.active, idle: 3600, enabled: false), .none)
    }

    func testWaitsWhileAnotherAppKeepsTheDisplayOn() {
        XCTAssertEqual(decide(.active, idle: 3600, held: true), .none)
    }

    func testTurnsOffOneMinuteAfterDimming() {
        XCTAssertEqual(decide(.dimmed, idle: 330, last: 329), .none)
        XCTAssertEqual(decide(.dimmed, idle: 360, last: 359), .off)
    }

    func testAnyInputWakesTheScreens() {
        XCTAssertEqual(decide(.dimmed, idle: 0.2, last: 320), .wake)
        XCTAssertEqual(decide(.off, idle: 3, last: 900), .wake)
        XCTAssertEqual(decide(.off, idle: 901, last: 900), .none)
    }
}

final class ConfigTests: XCTestCase {
    func testDefaultHotkeysDontCollide() {
        let combos = Hotkeys.defaults.values.map { "\($0.keyCode)-\($0.modifiers)" }
        XCTAssertEqual(combos.count, Set(combos).count, "two default hotkeys share a key combo")
    }

    func testInputSourceCodesAreUnique() {
        let codes = InputSource.allCases.map(\.rawValue)
        XCTAssertEqual(codes.count, Set(codes).count)
    }

    /// Settings saved by an older version (missing newer keys) must still load, with defaults for the new keys.
    func testOldSettingsStillLoad() throws {
        let key = "test.oldSettings.\(UUID().uuidString)"
        let old = ["mode": "sync", "brightnessStep": 5.0] as [String: Any]
        Store.defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: key)
        defer { Store.defaults.removeObject(forKey: key) }
        let s = Store.loadMerged(key, fallback: AppSettings())
        XCTAssertEqual(s.mode, .sync)
        XCTAssertEqual(s.brightnessStep, 5)
        XCTAssertFalse(s.awayEnabled)
        XCTAssertEqual(s.awayMinutes, 5)
    }
}
