import Foundation

enum AppInfo {
    static let bundleID = "design.jordancampbell.umbra"
    /// Bundle ID used before version 1.0. Settings saved under it are copied over once.
    static let legacyBundleID = "com.umbra.app"

    /// Copy settings saved under the old bundle ID into the current one, once.
    static func migrateLegacyDefaults() {
        let d = UserDefaults.standard
        guard !d.bool(forKey: "migratedLegacyDefaults") else { return }
        d.set(true, forKey: "migratedLegacyDefaults")
        guard Bundle.main.bundleIdentifier == bundleID,
              let old = UserDefaults(suiteName: legacyBundleID)?.persistentDomain(forName: legacyBundleID) else { return }
        for (k, v) in old where d.object(forKey: k) == nil { d.set(v, forKey: k) }
    }
}

/// Shared secret between the app and its CLI. Commands sent over distributed notifications must carry it,
/// so other apps can't post commands to Umbra. The file is readable only by the current user.
enum CLIToken {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Umbra", isDirectory: true)
        return dir.appendingPathComponent("cli-token")
    }

    static func read() -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Create the token if it doesn't exist yet and return it. Called by the app at launch.
    @discardableResult
    static func ensure() -> String {
        if let t = read(), !t.isEmpty { return t }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        fm.createFile(atPath: url.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600])
        return token
    }
}
