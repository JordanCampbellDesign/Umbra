import XCTest
@testable import Umbra

/// Every profile in Monitors/ must pass these. A monitor someone reports becomes a new profile here,
/// and a fix for it has to keep all the other profiles passing.
final class DDCSimulatorTests: XCTestCase {
    override func setUp() { DDC.waitScale = 0 }
    override func tearDown() { DDC.waitScale = 1 }

    func testPacketsCarryValidChecksums() {
        let mon = SimulatedMonitor(MonitorProfile(name: "strict", controls: ["0x10": [0, 100]]))
        _ = mon.write(DDC.setPacket(code: 0x10, value: 42))
        _ = mon.write(DDC.getPacket(code: 0x10))
        XCTAssertEqual(mon.badChecksums, 0, "the monitor rejected one of Umbra's packets")
        XCTAssertEqual(mon.values[0x10]?.cur, 42)
    }

    func testParseReplyRejectsNoiseAndWrongCodes() {
        XCTAssertNil(DDC.parseReply(Array(repeating: 0, count: 11), code: 0x10))
        XCTAssertNil(DDC.parseReply(Array(repeating: 0xFF, count: 11), code: 0x10))
        var good: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x2A]
        good.append(DDC.checksum(0x50, good))
        XCTAssertEqual(DDC.parseReply(good, code: 0x10)?.0, 42)
        XCTAssertNil(DDC.parseReply(good, code: 0x12), "a reply for another control must be ignored")
    }

    func testEveryProfile() throws {
        let profiles = try MonitorProfiles.all()
        XCTAssertFalse(profiles.isEmpty)
        for profile in profiles {
            let mon = SimulatedMonitor(profile)
            let link = AVLink(transport: mon, name: profile.name)
            for code in profile.controls.keys.compactMap({ UInt8($0.dropFirst(2), radix: 16) }) where code != 0x60 && code != 0xD6 {
                let target = min(37, mon.values[code]!.max)
                // Writes are retried by the caller when a monitor drops some; three tries covers the flaky profiles.
                for _ in 0 ..< 3 where mon.values[code]?.cur != target { DDC.write(link, code: code, target) }
                XCTAssertEqual(mon.values[code]?.cur, target, "\(profile.name): writing 0x\(String(code, radix: 16)) didn't land")
                // Reads may fail on noisy monitors, but they must never return a wrong value.
                if let vcp = VCP(rawValue: code), let (cur, _) = DDC.read(link, vcp) {
                    XCTAssertEqual(cur, target, "\(profile.name): read returned a wrong value")
                }
            }
            XCTAssertEqual(mon.badChecksums, 0, "\(profile.name): rejected a packet")
        }
    }

    func testNoisyMonitorReadsFailCleanly() throws {
        let samsung = try XCTUnwrap(MonitorProfiles.all().first { $0.name.contains("C27F390") })
        let link = AVLink(transport: SimulatedMonitor(samsung), name: samsung.name)
        XCTAssertNil(DDC.read(link, .brightness), "noise must read as no answer, not as a value")
        XCTAssertTrue(DDC.write(link, .brightness, 20))
    }
}
