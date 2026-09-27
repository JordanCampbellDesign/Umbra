import CoreGraphics
import Foundation
import IOKit

/// VESA MCCS control codes used by the app.
enum VCP: UInt8, CaseIterable, Codable {
    case brightness = 0x10
    case contrast = 0x12
    case redGain = 0x16
    case greenGain = 0x18
    case blueGain = 0x1A
    case inputSource = 0x60
    case volume = 0x62
    case mute = 0x8D
    case power = 0xD6
    case colorPreset = 0x14
    case resetFactory = 0x04

    var name: String {
        switch self {
        case .brightness: return "brightness"
        case .contrast: return "contrast"
        case .redGain: return "red"
        case .greenGain: return "green"
        case .blueGain: return "blue"
        case .inputSource: return "input"
        case .volume: return "volume"
        case .mute: return "mute"
        case .power: return "power"
        case .colorPreset: return "preset"
        case .resetFactory: return "reset"
        }
    }
}

/// Common input source values (MCCS 0x60).
enum InputSource: UInt16, CaseIterable, Identifiable {
    case vga1 = 0x01, vga2 = 0x02, dvi1 = 0x03, dvi2 = 0x04
    case displayPort1 = 0x0F, displayPort2 = 0x10
    case hdmi1 = 0x11, hdmi2 = 0x12, hdmi3 = 0x13, hdmi4 = 0x14
    case usbC1 = 0x1B, usbC2 = 0x19, usbC3 = 0x1C, thunderbolt = 0x1A

    var id: UInt16 { rawValue }
    var label: String {
        switch self {
        case .vga1: return "VGA 1"
        case .vga2: return "VGA 2"
        case .dvi1: return "DVI 1"
        case .dvi2: return "DVI 2"
        case .displayPort1: return "DisplayPort 1"
        case .displayPort2: return "DisplayPort 2"
        case .hdmi1: return "HDMI 1"
        case .hdmi2: return "HDMI 2"
        case .hdmi3: return "HDMI 3"
        case .hdmi4: return "HDMI 4"
        case .usbC1: return "USB-C 1"
        case .usbC2: return "USB-C 2"
        case .usbC3: return "USB-C 3"
        case .thunderbolt: return "Thunderbolt"
        }
    }
}

/// Sends and receives the bytes of one DDC/CI conversation. The real one talks to a monitor over IOAVService;
/// tests use a simulated monitor (Tests/UmbraTests/SimulatedMonitor.swift).
protocol DDCTransport {
    func write(_ bytes: [UInt8]) -> IOReturn
    func read(count: Int) -> (IOReturn, [UInt8])
}

/// DDC over IOAVService on Apple Silicon: I2C address 0x37, sub-address 0x51.
struct AVServiceTransport: DDCTransport {
    let service: CFTypeRef
    func write(_ bytes: [UInt8]) -> IOReturn {
        guard let w = Private.avWrite else { return kIOReturnUnsupported }
        return w(service, DDC.address, DDC.subAddress, bytes, UInt32(bytes.count))
    }
    func read(count: Int) -> (IOReturn, [UInt8]) {
        guard let r = Private.avRead else { return (kIOReturnUnsupported, []) }
        var reply = [UInt8](repeating: 0, count: count)
        let status = r(service, DDC.address, DDC.subAddress, &reply, UInt32(count))
        return (status, reply)
    }
}

/// One DDC-capable link found in the IORegistry.
final class AVLink {
    let transport: DDCTransport
    let vendor: UInt32?
    let product: UInt32?
    let serial: UInt32?
    let name: String?
    let queue = DispatchQueue(label: "umbra.ddc")

    init(service: CFTypeRef, attrs: [String: Any]?) {
        transport = AVServiceTransport(service: service)
        let p = attrs?["ProductAttributes"] as? [String: Any]
        vendor = (p?["LegacyManufacturerID"] as? NSNumber)?.uint32Value
        product = (p?["ProductID"] as? NSNumber)?.uint32Value
        serial = (p?["SerialNumber"] as? NSNumber)?.uint32Value
        name = p?["ProductName"] as? String
    }

    init(transport: DDCTransport, name: String? = nil, vendor: UInt32? = nil, product: UInt32? = nil) {
        self.transport = transport
        self.name = name
        self.vendor = vendor
        self.product = product
        serial = nil
    }
}

enum DDC {
    static let address: UInt32 = 0x37
    static let subAddress: UInt32 = 0x51
    /// Scales the waits between DDC messages. Real monitors need them; tests set this to 0.
    static var waitScale: Double = 1
    private static func wait(_ micros: Int) { if waitScale > 0 { usleep(useconds_t(Double(micros) * waitScale)) } }

    /// Walk the IORegistry and pair each external DCPAVServiceProxy with the framebuffer before it.
    static func discoverLinks() -> [AVLink] {
        guard Private.avCreate != nil else { return [] }
        var links: [AVLink] = []
        var iter = io_iterator_t()
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }

        var lastAttrs: [String: Any]?
        while true {
            let entry = IOIteratorNext(iter)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            var nameBuf = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &nameBuf)
            let name = String(cString: nameBuf)

            if name.contains("AppleCLCD2") || name.contains("IOMobileFramebufferShim") {
                if let a = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] {
                    lastAttrs = a
                } else {
                    lastAttrs = nil
                }
            } else if name == "DCPAVServiceProxy" {
                let loc = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                guard loc == "External", let svc = Private.avCreate?(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
                // Tiled displays (like the LG UltraFine 5K) have two links under one framebuffer, so keep the attrs.
                links.append(AVLink(service: svc, attrs: lastAttrs))
            }
        }
        return links
    }

    /// Choose the best link for a CoreGraphics display by vendor, product, and serial.
    static func match(_ id: CGDirectDisplayID, links: [AVLink], used: Set<Int>) -> Int? {
        let v = CGDisplayVendorNumber(id), m = CGDisplayModelNumber(id), s = CGDisplaySerialNumber(id)
        var best: (Int, Int)?
        for (i, l) in links.enumerated() where !used.contains(i) {
            var score = 0
            if l.vendor == v { score += 1 }
            if l.product == m { score += 2 }
            if s != 0, l.serial == s { score += 4 }
            if best == nil || score > best!.1 { best = (i, score) }
        }
        return best?.0
    }

    static func checksum(_ start: UInt8, _ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(start) { $0 ^ $1 }
    }

    /// "Set VCP feature" message: length, opcode 0x03, code, value high, value low, checksum.
    static func setPacket(code: UInt8, value: UInt16) -> [UInt8] {
        var data: [UInt8] = [0x84, 0x03, code, UInt8(value >> 8), UInt8(value & 0xFF)]
        data.append(checksum(0x6E ^ UInt8(subAddress), data))
        return data
    }

    /// "Get VCP feature" request: length, opcode 0x01, code, checksum.
    static func getPacket(code: UInt8) -> [UInt8] {
        var req: [UInt8] = [0x82, 0x01, code]
        req.append(checksum(0x6E ^ UInt8(subAddress), req))
        return req
    }

    /// Parse a "Get VCP feature" reply: [src, len, 0x02, result, code, type, maxH, maxL, curH, curL, checksum].
    /// Returns (current, max), or nil for noise, a wrong code, an unsupported code, or a bad checksum.
    static func parseReply(_ reply: [UInt8], code: UInt8) -> (UInt16, UInt16)? {
        guard reply.count >= 11, checksum(0x50, Array(reply[0 ..< 10])) == reply[10],
              reply[2] == 0x02, reply[3] == 0x00, reply[4] == code else { return nil }
        return (UInt16(reply[8]) << 8 | UInt16(reply[9]), UInt16(reply[6]) << 8 | UInt16(reply[7]))
    }

    @discardableResult
    static func write(_ link: AVLink, _ vcp: VCP, _ value: UInt16) -> Bool {
        write(link, code: vcp.rawValue, value)
    }

    @discardableResult
    static func write(_ link: AVLink, code: UInt8, _ value: UInt16) -> Bool {
        let data = setPacket(code: code, value: value)
        var ok = false
        var lastStatus: IOReturn = kIOReturnSuccess
        link.queue.sync {
            // Many monitors miss the first message, so each command is sent twice.
            for _ in 0 ..< 2 {
                wait(10_000)
                let status = link.transport.write(data)
                if status == KERN_SUCCESS { ok = true } else { lastStatus = status }
            }
        }
        Diagnostics.shared.ddcWrite(link: link, code: code, ok: ok, status: lastStatus)
        return ok
    }

    /// Read a control. Returns (current, max) or nil when the monitor does not answer.
    static func read(_ link: AVLink, _ vcp: VCP) -> (UInt16, UInt16)? {
        let req = getPacket(code: vcp.rawValue)
        var result: (UInt16, UInt16)?
        var noisy = 0
        link.queue.sync {
            let debug = ProcessInfo.processInfo.environment["UMBRA_DEBUG"] != nil
            for attempt in 0 ..< 4 {
                var wrote = false
                for _ in 0 ..< 2 {
                    wait(10_000)
                    if link.transport.write(req) == KERN_SUCCESS { wrote = true }
                }
                guard wrote else { continue }
                wait(50_000 + attempt * 20_000)
                let (status, reply) = link.transport.read(count: 11)
                guard status == KERN_SUCCESS else { continue }
                if debug { FileHandle.standardError.write((reply.map { String(format: "%02X", $0) }.joined(separator: " ") + "\n").data(using: .utf8)!) }
                if let r = parseReply(reply, code: vcp.rawValue) { result = r; return }
                noisy += 1
            }
        }
        Diagnostics.shared.ddcRead(link: link, code: vcp.rawValue, ok: result != nil, noisyReplies: noisy)
        return result
    }
}

/// Network fallback: sends DDC commands to a relay (for example a Raspberry Pi running ddcutil behind a tiny HTTP server).
/// URL format: http://host:port/<control>/<value>
enum NetworkDDC {
    static func send(base: String, _ vcp: VCP, _ value: UInt16) {
        guard let url = URL(string: "\(base.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(vcp.name)/\(value)") else { return }
        var req = URLRequest(url: url, timeoutInterval: 3)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req).resume()
    }
}
