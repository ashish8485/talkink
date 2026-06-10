import SwiftUI
import SoyleKit

/// The app's main window: two tabs — History (transcriptions) and Settings.
struct RootView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var perms: PermissionsModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(0)
            SettingsView(settings: settings, perms: perms)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(1)
        }
        .frame(width: 500, height: 620)
        .onAppear {
            // Land on Settings for onboarding when an essential permission is missing.
            if !perms.essentialsGranted { selection = 1 }
        }
        .sheet(isPresented: Binding(
            get: { !settings.hasPickedLanguage },
            set: { _ in }
        )) {
            LanguageOnboardingView(settings: settings)
                .interactiveDismissDisabled(true)
        }
    }
}

/// First-run step: pick the dictation language. Auto-detect exists, but an
/// explicit choice transcribes noticeably better (the model is prompted with
/// the language) — real-user feedback drove this.
struct LanguageOnboardingView: View {
    @ObservedObject var settings: SettingsStore

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 18) {
            Text("👋").font(.system(size: 40))
            Text("Which language will you speak?")
                .font(.system(size: 21, weight: .bold))
            Text("Talkink transcribes best when it knows your language.\nYou can change it anytime in Settings.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(SoyleLanguage.allCases.filter { $0 != .auto }) { lang in
                    Button {
                        settings.language = lang
                        settings.hasPickedLanguage = true
                    } label: {
                        VStack(spacing: 5) {
                            Text(lang.flag).font(.system(size: 26))
                            Text(lang.displayName).font(.system(size: 12, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 11).fill(Color.nvidia.opacity(0.10)))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.nvidia.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                settings.language = .auto
                settings.hasPickedLanguage = true
            } label: {
                Text("🌐  I speak several — detect automatically")
                    .font(.system(size: 12.5, weight: .medium))
            }
            .buttonStyle(.link)
            .tint(.nvidia)
        }
        .padding(28)
        .frame(width: 430)
    }
}
