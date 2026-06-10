import SwiftUI
import AppKit
import SoyleKit

/// Onboarding + settings (the "Settings" tab). Live permission status with grant
/// buttons, dictation prefs, behaviour, and an update notice. NVIDIA-green accents.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var perms: PermissionsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                permissionsSection
                dictationSection
                behaviourSection
            }
            .formStyle(.grouped)
            footer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.nvidia)
                Image(systemName: "mic.fill").font(.system(size: 23, weight: .bold)).foregroundStyle(.black)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text("Söyle").font(.system(size: 22, weight: .bold))
                Text("Hold \(settings.pttKey.displayName), speak, release.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section {
            permRow(title: "Microphone", granted: perms.microphone,
                    hint: "To record your voice (nothing is sent over the Internet).",
                    button: perms.microphone ? nil : (Permissions.microphoneDenied ? "Open Settings" : "Allow")) {
                if Permissions.microphoneDenied { Permissions.openMicrophoneSettings() }
                else { Permissions.requestMicrophone { _ in perms.refresh() } }
            }
            permRow(title: "Input Monitoring", granted: perms.inputMonitoring,
                    hint: "To detect your key globally. macOS may not list Söyle by itself — drag Söyle.app from the Finder window into the list (or use “+”), then enable it.",
                    button: perms.inputMonitoring ? nil : "Allow") {
                // On macOS 26, answering the system prompt no longer adds the
                // app to the Input Monitoring list (verified with clean TCC
                // identities) — so we open the pane AND reveal Söyle.app in the
                // Finder for a direct drag into the list. The request still
                // fires for macOS versions where it registers properly.
                Permissions.requestInputMonitoring()
                Permissions.openInputMonitoringSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !Permissions.hasInputMonitoring { Permissions.revealAppInFinder() }
                }
            }
            permRow(title: "Accessibility", granted: perms.accessibility,
                    hint: "To paste automatically at the cursor. Without it, the text stays in the clipboard (⌘V). Not in the list? Add Söyle with “+”.",
                    button: perms.accessibility ? nil : "Allow") {
                // The AX prompt has its own "Open System Settings" button;
                // ours is only the fallback.
                Permissions.requestAccessibility()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if !Permissions.hasAccessibility { Permissions.openAccessibilitySettings() }
                }
            }
        } header: {
            Text("Permissions")
        } footer: {
            if perms.essentialsGranted {
                Label(perms.accessibility ? "Everything is ready." : "Ready (auto-paste off — clipboard only).",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.nvidia).font(.caption)
            } else {
                Text("Microphone + Input Monitoring are required to function.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func permRow(title: String, granted: Bool, hint: String,
                         button: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(granted ? Color.nvidia : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(hint).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let button {
                Button(button, action: action).buttonStyle(.bordered).tint(.nvidia)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Dictation

    private var dictationSection: some View {
        Section("Dictation") {
            Picker("Push-to-talk key", selection: $settings.pttKey) {
                ForEach(PushToTalk.Key.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Language", selection: $settings.language) {
                ForEach(SoyleLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Model", selection: $settings.model) {
                ForEach(SoyleModel.allCases, id: \.self) { Text($0.menuLabel).tag($0) }
            }
        }
    }

    // MARK: Behaviour

    private var behaviourSection: some View {
        Section("Behaviour") {
            Toggle("Paste automatically at the cursor", isOn: $settings.autoPaste)
            Toggle("Feedback sounds", isOn: $settings.playSounds)
            Toggle("Launch at login", isOn: $settings.launchAtLogin)
            Toggle("Check for updates automatically", isOn: $settings.checkForUpdates)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("v\(appVersion) · 100% local · NVIDIA Nemotron 3.5 + MLX")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "dev"
    }
}
