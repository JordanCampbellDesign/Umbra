import XCTest
@testable import Umbra

final class SafetyTests: XCTestCase {
    /// Links can come from web pages, so they must never run commands that turn screens off or take over input.
    func testLinksCannotRunDangerousCommands() {
        for cmd in ["blackout", "power", "clean", "sleep", "mirror", "main", "swap", "arrange", "ddc", "gamma"] {
            XCTAssertFalse(CLI.linkCommands.contains(cmd), "\(cmd) must not be reachable from a link")
        }
    }

    func testBrandFromVendorCode() {
        // EDID vendor codes pack three letters into 5 bits each: "SAM" = 0x4C2D.
        func code(_ s: String) -> UInt32 {
            let v = s.unicodeScalars.map { UInt32($0.value - 64) }
            return v[0] << 10 | v[1] << 5 | v[2]
        }
        XCTAssertEqual(code("SAM"), 0x4C2D)
        XCTAssertEqual(Brand.names["SAM"], "Samsung")
        XCTAssertEqual(Brand.names["GSM"], "LG")
        XCTAssertEqual(Brand.names["DEL"], "Dell")
    }
}
