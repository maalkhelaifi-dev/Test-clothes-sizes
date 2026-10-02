import SwiftUI

@main
struct MeasureMeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
        }
    }
}

/// Shows onboarding (welcome, adult notice, privacy and consent) until it has been completed.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .alert("Couldn’t load saved data", isPresented: Binding(
            get: { model.loadError != nil },
            set: { if !$0 { model.loadError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.loadError ?? "")
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            ProfilesListView()
                .tabItem { Label("Profiles", systemImage: "person.2") }
            SizeChartListView()
                .tabItem { Label("Size charts", systemImage: "tablecells") }
            SettingsView()
                .tabItem { Label("Privacy & settings", systemImage: "lock.shield") }
        }
    }
}
