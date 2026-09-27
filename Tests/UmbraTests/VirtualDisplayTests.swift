import CoreGraphics
import VirtualDisplay
import XCTest
@testable import Umbra

/// Runs Umbra's display code against virtual screens: real displays as far as macOS knows, but made in
/// software, so no monitor is needed. They create screens on the Mac running them, so they only run with
/// UMBRA_VIRTUAL_DISPLAYS=1 (scripts/e2e/virtual_displays.sh), and only ever touch the screens they create.
final class VirtualDisplayTests: XCTestCase {
    private var made: [UMBVirtualDisplay] = []

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UMBRA_VIRTUAL_DISPLAYS"] == "1",
                          "Set UMBRA_VIRTUAL_DISPLAYS=1 to run tests that create virtual screens.")
    }

    override func tearDown() {
        guard !made.isEmpty else { return }
        let ids = made.map(\.displayID)
        autoreleasepool {
            for v in made { GammaController.shared.set(v.displayID, GammaController.State()); v.destroy() }
            made = []
        }
        // macOS removes virtual screens right away while the displays are awake (the script keeps them awake).
        // After a disconnect it can hold one until the process exits, so the script runs each test in its own process.
        let end = Date().addingTimeInterval(3)
        while !Set(online()).isDisjoint(with: ids), Date() < end { spin(0.1) }
        AppState.shared.refreshDisplays()
    }

    private func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    private func waitFor(_ what: String, timeout: Double = 5, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !cond(), Date() < end { spin(0.1) }
        XCTAssertTrue(cond(), "timed out waiting for \(what)")
    }

    private func online() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n); return Array(ids.prefix(Int(n)))
    }

    private func active() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16); var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n); return Array(ids.prefix(Int(n)))
    }

    /// Make a virtual display and wait until Umbra sees it.
    private func make(_ name: String, vendor: UInt32 = 0x10AC, product: UInt32 = 0xA0B1, serial: UInt32 = 7,
                      width: UInt32 = 1920, height: UInt32 = 1080) throws -> Display {
        let v = try XCTUnwrap(autoreleasepool { UMBVirtualDisplay(name: name, width: width, height: height, vendorID: vendor, productID: product, serial: serial) },
                              "this macOS doesn't offer virtual displays")
        made.append(v)
        waitFor("\(name) to come online") { online().contains(v.displayID) }
        AppState.shared.refreshDisplays()
        return try XCTUnwrap(AppState.shared.displays.first { $0.id == v.displayID }, "Umbra didn't pick up \(name)")
    }

    /// The top of the red gamma curve: 1 at full brightness, lower when dimmed in software.
    private func gammaTop(_ id: CGDirectDisplayID) -> Double {
        var r = [CGGammaValue](repeating: 0, count: 256), g = r, b = r; var n: UInt32 = 0
        CGGetDisplayTransferByTable(id, 256, &r, &g, &b, &n)
        return n > 0 ? Double(r[Int(n) - 1]) : -1
    }

    func testDetectsANewMonitorWithItsBrand() throws {
        let d = try make("Umbra Test Dell")
        XCTAssertFalse(d.isBuiltin)
        XCTAssertNil(d.link, "a virtual screen has no DDC link")
        XCTAssertEqual(d.method, .gamma, "without DDC or Apple Native, Umbra should dim in software")
        XCTAssertEqual(Brand.of(d.id), "Dell")
        MainActor.assumeIsolated {
            XCTAssertTrue(DisplayEntity(d).words.contains("dell"), "Siri should know it as a Dell")
        }
    }

    func testSoftwareDimmingChangesTheScreen() throws {
        let d = try make("Umbra Test Gamma")
        d.setBrightness(100)
        waitFor("full brightness") { gammaTop(d.id) > 0.95 }
        d.setBrightness(40)
        // Gamma dimming maps 0-100% to a factor of 0.12-1.0.
        waitFor("40% brightness") { abs(gammaTop(d.id) - (0.12 + 0.88 * 0.4)) < 0.03 }
        d.awayBlack = true
        d.applyGamma()
        waitFor("Away mode black") { gammaTop(d.id) < 0.01 }
        d.awayBlack = false
        d.setBrightness(100)
        waitFor("back to full") { gammaTop(d.id) > 0.95 }
    }

    func testBlackOutDisconnectsAndRestores() throws {
        let d = try make("Umbra Test BlackOut", serial: 8)
        XCTAssertTrue(AppState.shared.setBlackOut(d, true, method: .disconnect))
        // macOS may refuse to disconnect a virtual screen; then Umbra mirrors it and blacks it out instead.
        waitFor("the screen to turn off") { !active().contains(d.id) || CGDisplayMirrorsDisplay(d.id) != kCGNullDirectDisplay }
        XCTAssertTrue(d.blackedOut)
        XCTAssertTrue(AppState.shared.setBlackOut(d, false, method: .disconnect))
        waitFor("the screen to come back") { active().contains(d.id) && CGDisplayMirrorsDisplay(d.id) == kCGNullDirectDisplay }
        XCTAssertFalse(d.blackedOut)
    }

    func testSwapThenUndoRestoresTheArrangement() throws {
        let a = try make("Umbra Test A", product: 0xA0B2, serial: 9)
        let b = try make("Umbra Test B", product: 0xA0B3, serial: 10)
        let before = (CGDisplayBounds(a.id).origin, CGDisplayBounds(b.id).origin)
        XCTAssertTrue(Arrangement.swap(a, b))
        waitFor("the swap") { CGDisplayBounds(a.id).origin != before.0 }
        XCTAssertEqual(CGDisplayBounds(a.id).origin.x, before.1.x, accuracy: 1)
        // Umbra asks "Keep this screen arrangement?"; choosing Go back (or waiting 15 s) restores it.
        waitFor("the keep-or-go-back prompt") { ArrangementConfirm.shared.isAsking }
        ArrangementConfirm.shared.revert()
        waitFor("the undo") { CGDisplayBounds(a.id).origin == before.0 && CGDisplayBounds(b.id).origin == before.1 }
    }
}
