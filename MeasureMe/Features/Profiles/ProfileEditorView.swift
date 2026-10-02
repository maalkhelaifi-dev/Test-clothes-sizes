import SwiftUI
import MeasureMeCore

/// Screen 2: person profile and height entry.
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let existing: PersonProfile?

    @State private var name = ""
    @State private var heightCM: Double?
    @State private var unit: LengthUnit = .centimetres
    @State private var fit: FitPreference = .regular
    @State private var audiences: Set<SizeAudience> = [.unisex]
    @State private var adultConfirmed = false
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name or nickname", text: $name)
                        .textContentType(.nickname)
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Only used to tell profiles apart on this device.")
                }

                Section {
                    Picker("Units", selection: $unit) {
                        ForEach(LengthUnit.allCases) { Text($0.displayName).tag($0) }
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        HeightField(heightCM: $heightCM, unit: unit)
                            .id(unit)
                    }
                } header: {
                    Text("Height")
                } footer: {
                    Text("Your height is the scale reference for camera measurements, so measure it carefully: barefoot, standing against a wall. An error of 2 cm in height changes every estimate by about 1%.")
                }

                Section {
                    Picker("Preferred fit", selection: $fit) {
                        ForEach(FitPreference.allCases) { Text($0.displayName).tag($0) }
                    }
                    ForEach(SizeAudience.allCases) { audience in
                        Toggle(audience.displayName, isOn: Binding(
                            get: { audiences.contains(audience) },
                            set: { on in if on { audiences.insert(audience) } else { audiences.remove(audience) } }
                        ))
                    }
                } header: {
                    Text("Sizing preferences")
                } footer: {
                    Text("Choose which chart lines you want to see. This is your choice — the app never infers it.")
                }

                Section {
                    Toggle("This profile is for an adult (18+)", isOn: $adultConfirmed)
                } footer: {
                    Text("Measure Me does not support measuring children.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New profile" : "Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let p = existing {
            name = p.displayName
            heightCM = p.heightCM
            unit = p.preferredUnit
            fit = p.defaultFit
            audiences = Set(p.preferredAudiences)
            adultConfirmed = p.adultConfirmed
        } else {
            unit = settings.defaultUnit
        }
    }

    private func save() {
        guard let heightCM else {
            errorMessage = "Enter your height."
            return
        }
        var profile = existing ?? PersonProfile(displayName: name, heightCM: heightCM, adultConfirmed: adultConfirmed)
        profile.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.heightCM = heightCM
        profile.preferredUnit = unit
        profile.defaultFit = fit
        profile.preferredAudiences = SizeAudience.allCases.filter { audiences.contains($0) }
        profile.adultConfirmed = adultConfirmed
        do {
            try model.save(profile: profile)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
