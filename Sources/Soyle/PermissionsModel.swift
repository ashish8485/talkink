import Foundation
import Combine

/// Live-updating permission status for the settings/onboarding window.
/// Polls every second so the UI reflects grants made in System Settings.
final class PermissionsModel: ObservableObject {
    @Published var microphone = false
    @Published var inputMonitoring = false
    @Published var accessibility = false      // for auto-paste

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
        let ax = Permissions.hasAccessibility
        if mic != microphone { microphone = mic }
        if im != inputMonitoring { inputMonitoring = im }
        if ax != accessibility { accessibility = ax }
    }

    /// Essentials needed for push-to-talk to work at all.
    var essentialsGranted: Bool { microphone && inputMonitoring }
}
