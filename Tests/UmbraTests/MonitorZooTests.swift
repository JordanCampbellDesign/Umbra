import XCTest
@testable import Umbra

/// A zoo of simulated monitors, far beyond the ones on any one desk. Each monitor mixes quirks seen in the
/// wild: value ranges other than 0-100, noisy or missing reads, dropped writes, I/O errors, and missing
/// controls (many monitors have no speakers). The mix is seeded, so a failure always reproduces.
enum MonitorZoo {
    static func generate(count: Int, seed: UInt64 = 2026) -> [MonitorProfile] {
        var rng = seed
        func next() -> Double { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Double(rng >> 11) / Double(1 << 53) }
        func pick<T>(_ options: [(T, Double)]) -> T {
            var r = next()
            for (v, w) in options { if r < w { return v }; r -= w }
            return options.last!.0
        }
        return (0 ..< count).map { i in
            let maxRange: UInt16 = pick([(100, 0.8), (255, 0.1), (50, 0.05), (64, 0.05)])
            var controls: [String: [UInt16]] = ["0x10": [maxRange / 2, maxRange], "0x12": [maxRange / 2, maxRange]]
            if next() > 0.4 { controls["0x62"] = [maxRange / 4, maxRange] }             // has speakers
            var p = MonitorProfile(name: "zoo-\(i) (max \(maxRange))", controls: controls)
            p.readNoise = pick([(0.0, 0.5), (0.2, 0.2), (0.5, 0.15), (1.0, 0.15)])
            p.dropWrites = pick([(0.0, 0.7), (0.1, 0.2), (0.3, 0.1)])
            p.writeErrors = pick([(0.0, 0.85), (0.05, 0.1), (0.2, 0.05)])
            if next() < 0.05 { p.unsupported = ["0x12"] }                                  // no DDC contrast
            return p
        }
    }
}

final class MonitorZooTests: XCTestCase {
    override func setUp() { DDC.waitScale = 0 }
    override func tearDown() { DDC.waitScale = 1 }

    func testZoo() {
        let zoo = MonitorZoo.generate(count: 2000)
        var fullRange = 0, noRangeFallback = 0
        for (i, profile) in zoo.enumerated() {
            let mon = SimulatedMonitor(profile, seed: UInt64(i) + 7)
            let link = AVLink(transport: mon, name: profile.name)

            // What Umbra does when a monitor connects: learn each control's range.
            let found = DDC.probeMax(link)
            for (vcp, mx) in found {
                XCTAssertEqual(mx, mon.values[vcp.rawValue]?.max, "\(profile.name): learned a wrong range for \(vcp)")
                XCTAssertFalse(profile.unsupported.contains(String(format: "0x%02X", vcp.rawValue)), "\(profile.name): claimed an unsupported control")
            }

            for vcp in [VCP.brightness, .contrast, .volume] {
                guard let actual = mon.values[vcp.rawValue], !profile.unsupported.contains(String(format: "0x%02X", vcp.rawValue)) else {
                    // Missing controls must be harmless to write.
                    DDC.write(link, vcp, 10)
                    continue
                }
                let assumedMax = found[vcp] ?? 100
                let value = DDC.hardwareValue(percent: 37, max: assumedMax)
                for _ in 0 ..< 3 where mon.values[vcp.rawValue]?.cur != min(value, actual.max) { DDC.write(link, vcp, value) }
                let landed = mon.values[vcp.rawValue]!.cur
                XCTAssertEqual(landed, min(value, actual.max), "\(profile.name): \(vcp) write didn't land")
                if found[vcp] != nil {
                    // With the learned range, 37% lands at 37% of the monitor's real range.
                    XCTAssertEqual(Double(landed) / Double(actual.max), 0.37, accuracy: 0.5 / Double(actual.max) + 0.001, "\(profile.name): \(vcp) off-scale")
                    if vcp == .brightness { fullRange += 1 }
                } else if vcp == .brightness, actual.max != 100 {
                    noRangeFallback += 1
                }
                // Reads may fail, but never return a wrong value.
                if let (cur, _) = DDC.read(link, vcp) { XCTAssertEqual(cur, landed, "\(profile.name): read a wrong value") }
            }
            XCTAssertEqual(mon.badChecksums, 0, "\(profile.name): rejected a packet")
        }
        print("Monitor zoo: \(zoo.count) monitors; brightness range learned for \(fullRange); \(noRangeFallback) use a non-100 range but never answer reads, so Umbra assumes 0-100 for them.")
    }
}
