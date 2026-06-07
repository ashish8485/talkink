import Foundation
import Combine

/// Live-updating permission status for the settings/onboarding window.
/// Polls every second so the UI reflects grants made in System Settings
/// without needing a relaunch of this window.
final class PermissionsModel: ObservableObject {
    @Published var microphone = false
    @Published var inputMonitoring = false

    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate() }

    func refresh() {
        let mic = Permissions.hasMicrophone
        let im = Permissions.hasInputMonitoring
        if mic != microphone { microphone = mic }
        if im != inputMonitoring { inputMonitoring = im }
    }

    var allGranted: Bool { microphone && inputMonitoring }
}
