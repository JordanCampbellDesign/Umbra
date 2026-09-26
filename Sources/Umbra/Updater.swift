import AppKit
#if canImport(Sparkle)
import Sparkle
#endif

/// Automatic updates through Sparkle, using the appcast in the GitHub repo.
/// The Swift package build has no Sparkle, so updates are off there.
final class Updater {
    static let shared = Updater()

    #if canImport(Sparkle)
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    var available: Bool { true }
    func checkForUpdates() { controller.checkForUpdates(nil) }
    #else
    var available: Bool { false }
    func checkForUpdates() {}
    #endif
}
