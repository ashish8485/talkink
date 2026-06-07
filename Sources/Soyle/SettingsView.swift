import SwiftUI
import SoyleKit

/// Unified onboarding + settings window. Shows permission status (live) with
/// grant buttons, and all preferences. NVIDIA-green accented.
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
                feedbackSection
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 480, height: 600)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.nvidia)
                Image(systemName: "mic.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(.black)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text("Söyle").font(.system(size: 24, weight: .bold))
                Text("Maintiens \(settings.pttKey.displayName), parle, relâche. Le texte est copié.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    // MARK: Permissions

    private var permissionsSection: some View {
        Section {
            permRow(
                title: "Microphone",
                granted: perms.microphone,
                hint: "Pour enregistrer ta voix (rien n'est envoyé sur Internet).",
                buttonTitle: perms.microphone ? nil : (Permissions.microphoneDenied ? "Ouvrir Réglages" : "Autoriser")
            ) {
                if Permissions.microphoneDenied { Permissions.openMicrophoneSettings() }
                else { Permissions.requestMicrophone { _ in perms.refresh() } }
            }
            permRow(
                title: "Surveillance des saisies",
                granted: perms.inputMonitoring,
                hint: "Pour détecter ta touche globalement. Relance Söyle après activation.",
                buttonTitle: perms.inputMonitoring ? nil : "Autoriser"
            ) {
                Permissions.requestInputMonitoring()
                Permissions.openInputMonitoringSettings()
            }
        } header: {
            Text("Autorisations")
        } footer: {
            if perms.allGranted {
                Label("Tout est prêt.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.nvidia).font(.caption)
            } else {
                Text("Söyle a besoin de ces deux autorisations pour fonctionner.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func permRow(title: String, granted: Bool, hint: String,
                         buttonTitle: String?, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(granted ? Color.nvidia : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let buttonTitle {
                Button(buttonTitle, action: action).buttonStyle(.bordered).tint(.nvidia)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Dictation settings

    private var dictationSection: some View {
        Section("Dictée") {
            Picker("Touche push-to-talk", selection: $settings.pttKey) {
                ForEach(PushToTalk.Key.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Langue", selection: $settings.language) {
                ForEach(SoyleLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Picker("Modèle", selection: $settings.model) {
                ForEach(SoyleModel.allCases, id: \.self) { Text($0.menuLabel).tag($0) }
            }
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle("Sons de retour", isOn: $settings.playSounds)
            Toggle("Lancer au démarrage", isOn: $settings.launchAtLogin)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("v0.1.0 · 100 % local · NVIDIA Nemotron 3.5 + MLX")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}
