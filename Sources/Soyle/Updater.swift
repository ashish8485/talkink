import Foundation
import Sparkle

/// Sparkle auto-updates. The feed is appcast.xml on the repo's main branch;
/// release archives are EdDSA-signed (SUPublicEDKey in Info.plist).
/// Replaces the v0.1–v0.2 GitHub "new version available" notifier.
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    /// Mirrors Settings → "Check for updates automatically".
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
