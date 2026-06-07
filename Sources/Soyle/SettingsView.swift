import SwiftUI
import AppKit
import SoyleKit

/// Onboarding + settings (the "Réglages" tab). Live permission status with grant
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
                Text("Maintiens \(settings.pttKey.displayName), parle, relâche.")
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
                    hint: "Pour enregistrer ta voix (rien n'est envoyé sur Internet).",
                    button: perms.microphone ? nil : (Permissions.microphoneDenied ? "Ouvrir Réglages" : "Autoriser")) {
                if Permissions.microphoneDenied { Permissions.openMicrophoneSettings() }
                else { Permissions.requestMicrophone { _ in perms.refresh() } }
            }
            permRow(title: "Surveillance des saisies", granted: perms.inputMonitoring,
                    hint: "Pour détecter ta touche globalement. Relance Söyle après activation.",
                    button: perms.inputMonitoring ? nil : "Autoriser") {
                Permissions.requestInputMonitoring(); Permissions.openInputMonitoringSettings()
            }
            permRow(title: "Accessibilité", granted: perms.accessibility,
                    hint: "Pour coller automatiquement au curseur. Sans elle, le texte reste dans le presse-papier (⌘V).",
                    button: perms.accessibility ? nil : "Autoriser") {
                Permissions.requestAccessibility(); Permissions.openAccessibilitySettings()
            }
        } header: {
            Text("Autorisations")
        } footer: {
            if perms.essentialsGranted {
                Label(perms.accessibility ? "Tout est prêt." : "Prêt (auto-collage off — presse-papier seul).",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.nvidia).font(.caption)
            } else {
                Text("Micro + Surveillance des saisies sont nécessaires au fonctionnement.")
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

    // MARK: Behaviour

    private var behaviourSection: some View {
        Section("Comportement") {
            Toggle("Coller automatiquement au curseur", isOn: $settings.autoPaste)
            Toggle("Sons de retour", isOn: $settings.playSounds)
            Toggle("Lancer au démarrage", isOn: $settings.launchAtLogin)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 8) {
            if let up = update.latest {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(Color.nvidia)
                Text("Nouvelle version v\(up.version)").font(.caption).fontWeight(.semibold)
                Button("Voir") { NSWorkspace.shared.open(up.url) }.buttonStyle(.link).tint(.nvidia)
            } else {
                Text("v\(update.currentVersion) · 100 % local · NVIDIA Nemotron 3.5 + MLX")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }
}
