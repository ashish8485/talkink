import SwiftUI
import AppKit
import SoyleKit

/// Onboarding + settings (the "Settings" tab). Live permission status with grant
/// buttons, dictation prefs, behaviour, and an update notice. NVIDIA-green accents.
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var perms: PermissionsModel
    @ObservedObject var update = UpdateChecker.shared

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
        .onAppear { update.check() }
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
                    hint: "To detect your key globally. Restart Söyle after enabling.",
                    button: perms.inputMonitoring ? nil : "Allow") {
                Permissions.requestInputMonitoring(); Permissions.openInputMonitoringSettings()
            }
            permRow(title: "Accessibility", granted: perms.accessibility,
                    hint: "To paste automatically at the cursor. Without it, the text stays in the clipboard (⌘V).",
                    button: perms.accessibility ? nil : "Allow") {
                Permissions.requestAccessibility(); Permissions.openAccessibilitySettings()
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
            Toggle("Check for updates (GitHub)", isOn: $settings.checkForUpdates)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let up = update.latest {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.nvidia)
                Text("New version v\(up.version)").font(.caption).fontWeight(.semibold)
                Button("View") { NSWorkspace.shared.open(up.url) }.buttonStyle(.link).tint(.nvidia)
            } else {
                Text("v\(update.currentVersion) · 100% local · NVIDIA Nemotron 3.5 + MLX")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}
