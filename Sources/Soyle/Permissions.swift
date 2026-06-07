import Foundation
import AppKit
import AVFoundation
import CoreGraphics

/// Two permissions are needed (no Accessibility — Söyle is clipboard-only):
///  • Microphone — to record.
///  • Input Monitoring — for the listen-only global CGEventTap (push-to-talk).
enum Permissions {

    // MARK: Microphone
    static var hasMicrophone: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var microphoneDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .audio)
        return s == .denied || s == .restricted
    }

    static func requestMicrophone(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    // MARK: Input Monitoring (listen-only event tap)
    static var hasInputMonitoring: Bool {
        CGPreflightListenEventAccess()
    }

    /// Prompts once and opens the Input Monitoring pane. The grant only takes
    /// effect after the app is relaunched.
    static func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
    }

    // MARK: Settings deep-links
    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
