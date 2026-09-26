import XCTest
@testable import Umbra

final class SpringTests: XCTestCase {
    func testStepStartsAtZeroAndSettlesAtOne() {
        let s = Spring()
        XCTAssertEqual(s.step(0), 0)
        XCTAssertEqual(s.step(s.settleTime * 2), 1, accuracy: 1e-3)
    }

    func testOvershootIsTiny() {
        let s = Spring()
        var peak = 0.0
        var t = 0.0
        while t < 3 { peak = max(peak, s.step(t)); t += 0.001 }
        XCTAssertLessThan(peak - 1, 0.005, "overshoot should stay under 0.5%")
    }

    func testCriticallyDampedNeverOvershoots() {
        let s = Spring(response: 0.5, damping: 1)
        var t = 0.0
        while t < 3 { XCTAssertLessThanOrEqual(s.step(t), 1 + 1e-12); t += 0.001 }
    }

    func testRetargetDoesNotJump() {
        var track = SpringTrack(100)
        track.retarget(20, at: 0)
        let before = track.value(at: 0.2)
        track.retarget(60, at: 0.2)
        XCTAssertEqual(track.value(at: 0.2), before, accuracy: 1e-9)
        XCTAssertEqual(track.target, 60, accuracy: 1e-9)
        XCTAssertEqual(track.value(at: 5), 60, accuracy: 1e-3)
        XCTAssertTrue(track.isSettled(at: 5))
    }

    func testPruneKeepsValue() {
        var track = SpringTrack(0)
        track.retarget(50, at: 0)
        track.retarget(80, at: 0.1)
        let v = track.value(at: 10)
        track.prune(at: 10)
        XCTAssertEqual(track.value(at: 10), v, accuracy: 1e-6)
        XCTAssertEqual(track.base, 80, accuracy: 1e-9)
    }
}
