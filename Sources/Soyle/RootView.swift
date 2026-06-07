import SwiftUI

/// The app's main window: two tabs — Historique (transcriptions) and Réglages.
struct RootView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var perms: PermissionsModel
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            HistoryView()
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
                .tag(0)
            SettingsView(settings: settings, perms: perms)
                .tabItem { Label("Réglages", systemImage: "gearshape") }
                .tag(1)
        }
        .frame(width: 500, height: 620)
        .onAppear {
            // Land on Réglages for onboarding when an essential permission is missing.
            if !perms.essentialsGranted { selection = 1 }
        }
    }
}
