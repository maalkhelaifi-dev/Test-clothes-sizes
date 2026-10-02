import SwiftUI
import MeasureMeCore

/// Screen 8 (part 1): saved profiles.
@MainActor
struct ProfilesListView: View {
    @Environment(AppModel.self) private var model
    @State private var showingNewProfile = false

    var body: some View {
        NavigationStack {
            List {
                if model.profiles.isEmpty {
                    ContentUnavailableView {
                        Label("No profiles yet", systemImage: "person.crop.circle.badge.plus")
                    } description: {
                        Text("Create a profile for yourself or another adult to start measuring.")
                    } actions: {
                        Button("Create profile") { showingNewProfile = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
                ForEach(model.profiles) { profile in
                    NavigationLink(value: profile.id) {
                        ProfileRow(profile: profile)
                    }
                }
            }
            .navigationTitle("Profiles")
            .navigationDestination(for: UUID.self) { id in
                ProfileDetailView(profileID: id)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProfile = true
                    } label: {
                        Label("New profile", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProfile) {
                ProfileEditorView(existing: nil)
            }
        }
    }
}

@MainActor
struct ProfileRow: View {
    let profile: PersonProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.displayName).font(.headline)
            Text("Height \(profile.preferredUnit.format(centimetres: profile.heightCM)) · \(profile.sessions.count) measurement \(profile.sessions.count == 1 ? "session" : "sessions")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
