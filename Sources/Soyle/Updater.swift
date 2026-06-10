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
    /// macOS 26 — the agent exits ~0.5s in; upstream: Sparkle #273, #1717).
    /// The host-side relaunch hook never fires either (relaunch belongs to the
    /// dead agent), so the watcher is armed at willInstallUpdate — a hook that
    /// provably fires (the install itself always succeeds). The detached helper
    /// waits for THIS process to die, then opens the updated bundle; if any
    /// Sparkle relaunch also works, the extra `open` is a no-op.
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        NSLog("Soyle updater: willInstallUpdate %@ — arming relauncher", item.displayVersionString)
        spawnDetachedRelauncher()
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        NSLog("Soyle updater: willRelaunchApplication — arming relauncher")
        spawnDetachedRelauncher()
    }

    private var relauncherSpawned = false

    private func spawnDetachedRelauncher() {
        guard !relauncherSpawned else { return }
        relauncherSpawned = true
        let bundlePath = Bundle.main.bundlePath
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        LOG=/tmp/soyle_relauncher.log
        echo "$(date '+%H:%M:%S') armed: waiting for pid \(pid)" >> "$LOG"
        for i in $(seq 1 120); do
          if ! /bin/kill -0 \(pid) 2>/dev/null; then
            /bin/sleep 0.7
            echo "$(date '+%H:%M:%S') pid \(pid) gone — opening app" >> "$LOG"
            /usr/bin/open "\(bundlePath)" >> "$LOG" 2>&1
            exit 0
          fi
          /bin/sleep 0.5
        done
        echo "$(date '+%H:%M:%S') timeout — app never exited" >> "$LOG"
        """
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", script]
        try? helper.run()   // not waited on — must outlive us
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("Talkink updater aborted: %@ (code %ld)",
              error.localizedDescription, (error as NSError).code)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error {
            NSLog("Talkink update cycle ended with error: %@", String(describing: error))
        }
    }
}
