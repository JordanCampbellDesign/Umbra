import Foundation
import IOKit
@testable import Umbra

/// How one monitor model behaves on the DDC wire. Loaded from Tests/UmbraTests/Monitors/*.json.
struct MonitorProfile: Codable {
    var name: String
    /// VCP code (hex string, for example "0x10") -> [current, max].
    var controls: [String: [UInt16]]
    /// Chance (0...1) that a read reply is noise instead of a real answer.
    var readNoise: Double = 0
    /// Chance (0...1) that a write is lost on the wire (the transport still reports success).
    var dropWrites: Double = 0
    /// Chance (0...1) that a write returns an IOKit error.
    var writeErrors: Double = 0
    /// Codes the monitor answers "unsupported" for.
    var unsupported: [String] = []
    /// Microseconds the monitor needs after a "get" request before its reply is ready. Reading sooner returns zeros.
    var replyDelayMicros: Int = 0
    /// Microseconds the monitor needs between commands. A command that arrives sooner is ignored.
    var minGapMicros: Int = 0
    /// Notes for people reading the profile: connection, where it came from.
    var notes: String = ""

    init(name: String, controls: [String: [UInt16]]) { self.name = name; self.controls = controls }

    /// Missing quirks mean "none", so a profile only lists what's unusual about its monitor.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        controls = try c.decode([String: [UInt16]].self, forKey: .controls)
        readNoise = try c.decodeIfPresent(Double.self, forKey: .readNoise) ?? 0
        dropWrites = try c.decodeIfPresent(Double.self, forKey: .dropWrites) ?? 0
        writeErrors = try c.decodeIfPresent(Double.self, forKey: .writeErrors) ?? 0
        unsupported = try c.decodeIfPresent([String].self, forKey: .unsupported) ?? []
        replyDelayMicros = try c.decodeIfPresent(Int.self, forKey: .replyDelayMicros) ?? 0
        minGapMicros = try c.decodeIfPresent(Int.self, forKey: .minGapMicros) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

/// A fake monitor that speaks MCCS over DDC/CI. It checks the host's checksums like real hardware,
/// applies "set" commands, and answers "get" requests. Randomness is seeded so tests are repeatable.
final class SimulatedMonitor: DDCTransport {
    let profile: MonitorProfile
    private(set) var values: [UInt8: (cur: UInt16, max: UInt16)] = [:]
    private(set) var badChecksums = 0
    private var pendingReply: [UInt8]?
    private var replyReadyAt: UInt64 = 0
    private var lastCommandAt: UInt64?
    private(set) var ignoredTooSoon = 0
    private var rng: UInt64
    /// The clock Umbra waits on. Timing quirks only apply when the test gives the monitor one.
    var clock: DDCClock?

    init(_ profile: MonitorProfile, seed: UInt64 = 42, clock: DDCClock? = nil) {
        self.profile = profile
        self.clock = clock
        rng = seed
        for (k, v) in profile.controls {
            values[UInt8(k.dropFirst(2), radix: 16)!] = (v[0], v[1])
        }
    }

    private func chance(_ p: Double) -> Bool {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(rng >> 11) / Double(1 << 53) < p
    }

    func write(_ bytes: [UInt8]) -> IOReturn {
        if chance(profile.writeErrors) { return kIOReturnNotResponding }
        // Host messages end with a checksum over 0x6E ^ 0x51 and every byte before it.
        guard let last = bytes.last, DDC.checksum(0x6E ^ 0x51, Array(bytes.dropLast())) == last else {
            badChecksums += 1
            return kIOReturnSuccess                      // real monitors ignore bad packets silently
        }
        if chance(profile.dropWrites) { return kIOReturnSuccess }
        // Commands that arrive too soon after the last one are ignored, like on slow monitor firmware.
        if let clock, profile.minGapMicros > 0 {
            let now = clock.nowMicros
            if let last = lastCommandAt, now - last < UInt64(profile.minGapMicros) { ignoredTooSoon += 1; return kIOReturnSuccess }
            lastCommandAt = now
        }
        switch bytes.count >= 3 ? bytes[1] : 0 {
        case 0x03 where bytes.count >= 6:                // set VCP feature
            let code = bytes[2], value = UInt16(bytes[3]) << 8 | UInt16(bytes[4])
            if var v = values[code] { v.cur = min(value, v.max); values[code] = v }
        case 0x01:                                       // get VCP feature
            let code = bytes[2]
            let unsupported = profile.unsupported.contains { UInt8($0.dropFirst(2), radix: 16) == code } || values[code] == nil
            let v = values[code] ?? (0, 0)
            var reply: [UInt8] = [0x6E, 0x88, 0x02, unsupported ? 0x01 : 0x00, code, 0x00,
                                  UInt8(v.max >> 8), UInt8(v.max & 0xFF), UInt8(v.cur >> 8), UInt8(v.cur & 0xFF)]
            reply.append(DDC.checksum(0x50, reply))
            pendingReply = reply
            replyReadyAt = (clock?.nowMicros ?? 0) + UInt64(profile.replyDelayMicros)
        default:
            break
        }
        return kIOReturnSuccess
    }

    func read(count: Int) -> (IOReturn, [UInt8]) {
        // Asked too early: the reply isn't ready yet, so the line reads as zeros (and the request is kept).
        if let clock, pendingReply != nil, clock.nowMicros < replyReadyAt { return (kIOReturnSuccess, Array(repeating: 0, count: count)) }
        defer { pendingReply = nil }
        if chance(profile.readNoise) || pendingReply == nil {
            // What noisy links send back: zeros, all-ones, or a shifted echo.
            let junk: [[UInt8]] = [Array(repeating: 0, count: count), Array(repeating: 0xFF, count: count),
                                   [0x84, 0x38, 0x07, 0x00, 0x84, 0x38, 0x3F] + Array(repeating: 0xFF, count: max(0, count - 7))]
            return (kIOReturnSuccess, junk[Int(rng % 3)])
        }
        return (kIOReturnSuccess, Array(pendingReply!.prefix(count)))
    }
}

enum MonitorProfiles {
    static func all() throws -> [MonitorProfile] {
        let dir = Bundle.module.url(forResource: "Monitors", withExtension: nil)!
        return try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try JSONDecoder().decode(MonitorProfile.self, from: Data(contentsOf: $0)) }
    }
}

/// A clock that moves forward only when Umbra waits, so timing tests run instantly and exactly.
final class VirtualClock: DDCClock {
    private(set) var nowMicros: UInt64 = 1_000_000
    func sleep(_ micros: Int) { nowMicros += UInt64(max(0, micros)) }
}
