import Foundation
import Sparkle

/// Sparkle auto-updates. The feed is appcast.xml on the repo's main branch;
/// release archives are EdDSA-signed (SUPublicEDKey in Info.plist).
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController!

    /// Mirrors Settings → "Check for updates automatically".
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    /// Sparkle's installer agent proved unreliable at relaunching when the
    /// updated app sits at the same path as the quitting instance (verified on
    /// macOS 26; long-standing upstream reports: Sparkle #273, #1717). Spawn a
    /// tiny detached helper that waits for THIS process to die, then opens the
    /// updated bundle. If Sparkle's own relaunch also works, the extra `open`
    /// just activates the already-running app — harmless.
    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        for i in $(seq 1 60); do
          if ! /bin/kill -0 \(pid) 2>/dev/null; then
            /usr/bin/open "\(bundlePath)"
            exit 0
          fi
          /bin/sleep 0.5
        done
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        try? helper.run()   // not waited on — must outlive us
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("Söyle updater aborted: %@ (code %ld)",
              error.localizedDescription, (error as NSError).code)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            NSLog("Söyle update cycle ended with error: %@", String(describing: error))
        }
    }
}
