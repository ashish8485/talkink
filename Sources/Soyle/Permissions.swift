import Foundation
import AppKit
import AVFoundation
import CoreGraphics
import ApplicationServices

/// Permissions used by Söyle:
///  • Microphone — to record (required).
///  • Input Monitoring — listen-only global CGEventTap for push-to-talk (required).
///  • Accessibility — auto-paste at the cursor (optional; clipboard-only without it).
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

    /// Prompts once and opens the Input Monitoring pane. AppDelegate re-arms the
    /// tap automatically once the grant lands (relaunch only as a fallback).
    static func requestInputMonitoring() {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }
    }

    /// Reveal Söyle.app in a Finder window, so the user can drag it straight
    /// into the Input Monitoring list (on macOS 26 answering the system prompt
    /// no longer registers the app there — verified — manual add is the path).
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    // MARK: Settings deep-links
    static func openMicrophoneSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    static func openInputMonitoringSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    // MARK: Accessibility (required to auto-paste — synthetic ⌘V into other apps)
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func open(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }
}
