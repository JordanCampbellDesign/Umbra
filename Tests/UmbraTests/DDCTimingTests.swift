import XCTest
@testable import Umbra

/// Monitors that need time: slow replies, and firmware that ignores commands sent too close together.
/// A virtual clock stands in for real waits, so these run instantly.
final class DDCTimingTests: XCTestCase {
    var clock: VirtualClock!
    override func setUp() { clock = VirtualClock(); DDC.clock = clock }
    override func tearDown() { DDC.clock = RealClock() }

    func monitor(replyDelay: Int = 0, minGap: Int = 0) -> (SimulatedMonitor, AVLink) {
        var p = MonitorProfile(name: "timing", controls: ["0x10": [50, 100], "0x12": [50, 100]])
        p.replyDelayMicros = replyDelay
        p.minGapMicros = minGap
        let m = SimulatedMonitor(p, clock: clock)
        return (m, AVLink(transport: m, name: "timing"))
    }

    /// Umbra waits 50 ms before the first read and 20 ms more on each retry, up to 110 ms.
    func testSlowRepliesStillRead() {
        for delay in [0, 30_000, 60_000, 100_000] {
            let (m, link) = monitor(replyDelay: delay)
            DDC.write(link, .brightness, 42)
            XCTAssertEqual(m.values[0x10]?.cur, 42)
            XCTAssertEqual(DDC.read(link, .brightness)?.0, 42, "a monitor that answers after \(delay / 1000) ms should read")
        }
    }

    /// Too slow to answer: the read fails cleanly instead of returning a wrong value.
    func testTooSlowRepliesFailCleanly() {
        let (_, link) = monitor(replyDelay: 200_000)
        XCTAssertNil(DDC.read(link, .brightness))
    }

    /// A fast slider drag sends many commands close together. Firmware that needs a gap ignores some,
    /// which can leave the monitor on an older value. Umbra re-sends the final value after the drag.
    func testSliderDragEndsOnTheFinalValue() {
        for gap in [20_000, 50_000, 100_000, 150_000] {
            let (m, link) = monitor(minGap: gap)
            var finals: [UInt8: UInt16] = [:]
            for v in stride(from: 10, through: 86, by: 4) {
                DDC.write(link, .brightness, UInt16(v))
                finals[0x10] = UInt16(v)
            }
            if gap >= 100_000 {
                // Without the re-send, slow firmware is left on an older value: this is the bug the re-send fixes.
                XCTAssertNotEqual(m.values[0x10]?.cur, 86, "expected the drag alone to leave a \(gap / 1000) ms monitor behind")
            }
            DDC.settle(link, finals: finals)
            XCTAssertEqual(m.values[0x10]?.cur, 86, "with a \(gap / 1000) ms gap the monitor should end on the slider's value")
        }
    }
}
