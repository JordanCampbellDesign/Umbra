import AppKit
import Foundation

/// `umbra` command line tool. The same binary runs as the CLI when started with arguments.
enum CLI {
    static let notification = Notification.Name("design.jordancampbell.umbra.cli")
    static let replyNotification = Notification.Name("design.jordancampbell.umbra.cli.reply")

    static let usage = """
    Usage: umbra <command> [args]

      displays                         List displays and their values
      get <display> <property>         Read brightness, contrast, volume, input, subzero, xdr
      set <display> <property> <value> Set brightness|contrast|volume|mute|input|subzero|xdr|xdrlevel|red|green|blue
      ddc <display> <vcp-hex> [value]  Read a DDC control, or send any DDC command (ddc 2 0xD6 5)
      blackout <display> on|off        Turn a display off or back on
      facelight                        Toggle FaceLight
      xdr on|off                       Toggle XDR Brightness
      mode manual|sync|location|clock|sensor
      preset <name>                    Apply a saved preset
      preset save <name>               Save the current values as a preset
      gamma <display> <r> <g> <b>      Set software color gains from 0 to 1
      reset-colors <display>           Reset color gains to neutral
      power <display> on|off           DDC power (monitor standby)
      night on|off|toggle              Night Mode (dim, lower contrast, warm colors)
      open                             Show the main window
      clean                            Cleaning Mode (black screens, keyboard ignored)
      sleep                            Put the Mac to sleep
      mirror <display>|off             Mirror all screens to one display, or stop
      main <display>                   Make a display the main one
      swap <display> <display>         Swap two display positions
      arrange horizontal|vertical|above

    <display> is an index from `umbra displays`, a name fragment, "all", or "cursor".
    """

    /// Entry from the terminal: runs against the live app if it is open.
    static func main(_ args: [String]) -> Int32 {
        if args.first == "help" || args.first == "--help" || args.isEmpty { print(usage); return 0 }
        if args.first == "render" { return Render.run(args.count > 1 ? args[1] : "renders") }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: AppInfo.bundleID).contains { $0.processIdentifier != getpid() }
        let readOnly = ["displays", "get"].contains(args[0]) || (args[0] == "ddc" && args.count == 3)
        let known = ["displays", "get", "set", "ddc", "blackout", "facelight", "xdr", "mode", "preset", "gamma",
                     "reset-colors", "power", "open", "night", "clean", "sleep", "mirror", "main", "swap", "arrange"]
        guard known.contains(args[0]) else { print("error: unknown command \(args[0])\n\n" + usage); return 1 }
        if args[0] == "open" {
            // Launching or reopening the app shows its main window.
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: AppInfo.bundleID) else { print("error: Umbra.app not found"); return 1 }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.arguments = ["--window"]
            cfg.activates = true
            var done = false
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in done = true }
            let deadline = Date().addingTimeInterval(5)
            while !done, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            print("ok")
            return 0
        }
        if running {
            // Ask the running app and wait for its answer, so output shows live values.
            let id = UUID().uuidString
            var answer: String?
            let center = DistributedNotificationCenter.default()
            let obs = center.addObserver(forName: replyNotification, object: id, queue: .main) { n in
                answer = n.userInfo?["out"] as? String
            }
            guard let token = CLIToken.read() else { print("error: can't read Umbra's CLI token. Open Umbra once, then try again."); return 1 }
            center.postNotificationName(notification, object: nil, userInfo: ["args": args, "id": id, "token": token], deliverImmediately: true)
            let deadline = Date().addingTimeInterval(readOnly && args[0] == "ddc" ? 8 : 3)
            while answer == nil, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            center.removeObserver(obs)
            let out = answer ?? "error: Umbra did not answer"
            print(out)
            return out.hasPrefix("error") ? 1 : 0
        }
        // Standalone: build state in this process.
        _ = NSApplication.shared
        AppState.shared.refreshDisplays()
        Thread.sleep(forTimeInterval: readOnly ? 0.6 : 0.1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let out = runInApp(args)
        print(out)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        return out.hasPrefix("error") ? 1 : 0
    }

    static func resolve(_ q: String) -> [Display] {
        let s = AppState.shared
        switch q.lowercased() {
        case "all": return s.displays
        case "cursor": return s.displayUnderCursor().map { [$0] } ?? []
        case "builtin": return s.displays.filter(\.isBuiltin)
        default:
            if let i = Int(q), i >= 1, i <= s.displays.count { return [s.displays[i - 1]] }
            return s.displays.filter { $0.name.lowercased().contains(q.lowercased()) || $0.uuid == q }
        }
    }

    @discardableResult
    static func runInApp(_ args: [String]) -> String {
        let s = AppState.shared
        guard let cmd = args.first else { return usage }
        func num(_ i: Int) -> Double? { args.count > i ? Double(args[i]) : nil }

        switch cmd {
        case "displays":
            return s.displays.enumerated().map { i, d in
                let c = d.config
                var line = "\(i + 1). \(d.name) [\(d.method.label)] id=\(d.id) brightness=\(Int(c.brightness))"
                if d.hasHardwareControls { line += " contrast=\(Int(c.contrast)) volume=\(Int(c.volume))" }
                if c.subzero > 0 { line += " subzero=\(Int(c.subzero * 100))" }
                if c.xdr { line += " xdr=\(Int(c.xdrLevel * 100))" }
                if d.blackedOut { line += " (off)" }
                return line
            }.joined(separator: "\n")

        case "get":
            guard args.count >= 3 else { return "error: get <display> <property>" }
            return resolve(args[1]).map { d in
                let c = d.config
                switch args[2] {
                case "brightness": return "\(Int(c.brightness))"
                case "contrast": return "\(Int(c.contrast))"
                case "volume": return "\(Int(c.volume))"
                case "input": return d.inputSource.map { String(format: "0x%02X", $0) } ?? "unknown"
                case "subzero": return "\(Int(c.subzero * 100))"
                case "xdr": return c.xdr ? "on" : "off"
                default: return "error: unknown property"
                }
            }.joined(separator: "\n")

        case "set":
            guard args.count >= 4 else { return "error: set <display> <property> <value>" }
            let targets = resolve(args[1])
            guard !targets.isEmpty else { return "error: no display matches \(args[1])" }
            let raw = args[3]
            let v = Double(raw) ?? 0
            for d in targets {
                switch args[2] {
                case "brightness": s.userSetBrightness(d, v)
                case "contrast": d.setContrast(v)
                case "volume": d.setVolume(v)
                case "mute": d.setMuted(raw == "on" || raw == "1" || raw == "true")
                case "input":
                    let val = raw.hasPrefix("0x") ? UInt16(raw.dropFirst(2), radix: 16) : UInt16(raw)
                    let named = InputSource.allCases.first { $0.label.lowercased().replacingOccurrences(of: " ", with: "") == raw.lowercased() }?.rawValue
                    guard let input = val ?? named else { return "error: bad input \(raw)" }
                    d.setInput(input)
                case "subzero": d.setSubzero(v / 100)
                case "xdr": d.setXDR(raw == "on" || raw == "1")
                case "xdrlevel": d.setXDRLevel(v / 100)
                case "red": d.setColor(red: v)
                case "green": d.setColor(green: v)
                case "blue": d.setColor(blue: v)
                default: return "error: unknown property \(args[2])"
                }
            }
            return "ok"

        case "ddc":
            guard args.count >= 3 else { return "error: ddc <display> <vcp> [value]" }
            let codeStr = args[2].hasPrefix("0x") ? String(args[2].dropFirst(2)) : args[2]
            if args.count == 3 {
                guard let code = UInt8(codeStr, radix: 16), let vcp = VCP(rawValue: code) else { return "error: can read only known VCP codes" }
                return resolve(args[1]).map { d in
                    guard let link = d.link, let (cur, mx) = DDC.read(link, vcp) else { return "\(d.name): no reply" }
                    return "\(d.name): current=\(cur) max=\(mx)"
                }.joined(separator: "\n")
            }
            guard let code = UInt8(codeStr, radix: 16), let val = UInt16(args[3]) else { return "error: bad vcp or value" }
            resolve(args[1]).forEach { $0.sendRaw(code: code, value: val) }
            Thread.sleep(forTimeInterval: 0.2)
            return "ok"

        case "blackout":
            guard args.count >= 3 else { return "error: blackout <display> on|off" }
            let on = args[2] == "on"
            return resolve(args[1]).map { s.setBlackOut($0, on) ? "ok" : "error: could not change \($0.name)" }.joined(separator: "\n")

        case "facelight": s.toggleFaceLight(); return "ok"

        case "xdr":
            let on = args.count < 2 || args[1] == "on"
            s.displays.filter(\.supportsXDR).forEach { $0.setXDR(on) }
            return "ok"

        case "mode":
            guard args.count >= 2, let m = AdaptiveMode(rawValue: args[1]) else { return "error: mode manual|sync|location|clock|sensor" }
            s.settings.mode = m
            return "ok"

        case "preset":
            guard args.count >= 2 else { return "error: preset <name>" }
            if args[1] == "save", args.count >= 3 { s.savePreset(named: args[2...].joined(separator: " ")); return "ok" }
            return s.applyPreset(named: args[1...].joined(separator: " ")) ? "ok" : "error: no preset named \(args[1])"

        case "gamma":
            guard args.count >= 5, let r = num(2), let g = num(3), let b = num(4) else { return "error: gamma <display> <r> <g> <b>" }
            resolve(args[1]).forEach { $0.setColor(red: r, green: g, blue: b) }
            return "ok"

        case "reset-colors":
            resolve(args.count > 1 ? args[1] : "all").forEach { $0.setColor(red: 1, green: 1, blue: 1) }
            return "ok"

        case "power":
            guard args.count >= 3 else { return "error: power <display> on|off" }
            resolve(args[1]).forEach { s.setBlackOut($0, args[2] == "off", method: .ddcPower) }
            return "ok"

        case "night":
            switch args.count > 1 ? args[1] : "toggle" {
            case "on": NightMode.shared.set(true)
            case "off": NightMode.shared.set(false)
            default: NightMode.shared.toggle()
            }
            return "ok"

        case "clean": CleaningMode.shared.start(); return "ok"
        case "open":
            guard let delegate = NSApp.delegate as? AppDelegate else { return "error: Umbra is not running" }
            delegate.openMainWindow()
            return "ok"
        case "sleep": Power.sleepMac(); return "ok"

        case "mirror":
            guard args.count >= 2 else { return "error: mirror <display>|off" }
            if args[1] == "off" { return Arrangement.stopMirroring(s.displays) ? "ok" : "error: could not stop mirroring" }
            guard let d = resolve(args[1]).first else { return "error: no display matches \(args[1])" }
            return Arrangement.mirror(to: d, s.displays) ? "ok" : "error: could not mirror"

        case "main":
            guard args.count >= 2, let d = resolve(args[1]).first else { return "error: main <display>" }
            return Arrangement.setMain(d, s.displays) ? "ok" : "error: could not change the main display"

        case "swap":
            guard args.count >= 3, let a = resolve(args[1]).first, let b = resolve(args[2]).first else { return "error: swap <display> <display>" }
            return Arrangement.swap(a, b) ? "ok" : "error: could not swap"

        case "arrange":
            let how = args.count > 1 ? args[1] : "horizontal"
            let ok = how == "above" ? Arrangement.above(s.displays) : Arrangement.line(s.displays, vertical: how == "vertical")
            return ok ? "ok" : "error: could not arrange"

        default:
            return "error: unknown command \(cmd)\n\n" + usage
        }
    }

    /// Handle umbra:// links, for example umbra://set?display=all&brightness=40 or umbra://preset/Night.
    /// Commands a `umbra://` link may run. Links can come from web pages, so anything that turns screens off,
    /// rearranges them, blocks the keyboard, or sleeps the Mac is left out.
    static let linkCommands: Set<String> = ["set", "preset", "night", "facelight", "xdr", "mode", "open", "reset-colors"]

    static func handle(url: URL) {
        guard let host = url.host, linkCommands.contains(host) else {
            OSD.shared.showText("Umbra ignored a link it doesn't allow", symbol: "hand.raised")
            return
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let q = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        let path = url.pathComponents.filter { $0 != "/" }
        switch host {
        case "set":
            let d = q["display"] ?? "all"
            for (k, v) in q where k != "display" && ["brightness", "contrast", "volume", "mute", "subzero"].contains(k) {
                runInApp(["set", d, k, v])
            }
        default:
            runInApp([host] + path)
        }
    }

    /// Put a `umbra` command on the PATH that runs this binary.
    static func install() -> String {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let script = "#!/bin/sh\nexec \"\(exe)\" --cli \"$@\"\n"
        let candidates = ["/usr/local/bin", "/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin"]
        for dir in candidates {
            let fm = FileManager.default
            if dir.hasSuffix(".local/bin") { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
            guard fm.isWritableFile(atPath: dir) else { continue }
            let path = dir + "/umbra"
            do {
                try? fm.removeItem(atPath: path)
                try script.write(toFile: path, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
                return path
            } catch { continue }
        }
        return ""
    }
}
