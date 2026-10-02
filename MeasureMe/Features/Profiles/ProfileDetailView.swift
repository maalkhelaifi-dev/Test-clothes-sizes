import SwiftUI
import MeasureMeCore

@MainActor
struct ProfileDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    let profileID: UUID

    @State private var flowMode: MeasureFlowMode?
    @State private var showingEditor = false
    @State private var confirmDelete = false
    @State private var showingConsent = false
    @State private var errorMessage: String?

    var body: some View {
        if let profile = model.profile(id: profileID) {
            content(profile)
        } else {
            ContentUnavailableView("Profile deleted", systemImage: "person.crop.circle.badge.xmark")
        }
    }

    private func content(_ profile: PersonProfile) -> some View {
        let latest = profile.latestMeasurements
        return List {
            Section {
                Button {
                    if settings.cameraConsentGiven { flowMode = .camera } else { showingConsent = true }
                } label: {
                    Label("Measure with camera", systemImage: "camera.viewfinder")
                        .font(.headline)
                }
                .accessibilityHint("Starts a guided front and side photo capture")
                Button {
                    flowMode = .manual
                } label: {
                    Label("Enter measurements manually", systemImage: "ruler")
                }
                NavigationLink {
                    RecommendationView(profileID: profileID)
                } label: {
                    Label("Find my size", systemImage: "tag")
                }
            }

            Section("Latest measurements") {
                let values = latest.sorted
                if values.count <= 1 {
                    Text("No measurements yet. Use the camera or enter them manually.")
                        .foregroundStyle(.secondary)
                }
                ForEach(values) { value in
                    MeasurementSummaryRow(value: value, unit: profile.preferredUnit)
                }
            }

            Section("History") {
                if profile.sessions.isEmpty {
                    Text("Saved measurement sessions will appear here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(profile.history) { session in
                    NavigationLink {
                        SessionDetailView(profileID: profileID, sessionID: session.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.date.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text("\(session.method.displayName) · \(session.measurements.sorted.count) measurements\(session.category.map { " · \($0.displayName)" } ?? "")")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { profile.history[$0].id }
                    do {
                        for id in ids { try model.deleteSession(id, from: profileID) }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }

            Section {
                Button("Edit profile") { showingEditor = true }
                Button("Delete profile and all its data", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(profile.displayName)
        .sheet(isPresented: $showingEditor) {
            ProfileEditorView(existing: profile)
        }
        .fullScreenCover(item: $flowMode) { mode in
            MeasureFlowView(profile: profile, mode: mode)
        }
        .confirmationDialog("Delete \(profile.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                do {
                    try model.deleteProfile(id: profileID)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("This permanently deletes the profile, its measurement history and any saved capture photos from this iPhone.")
        }
        .alert("Camera consent", isPresented: $showingConsent) {
            Button("I agree") {
                settings.cameraConsentGiven = true
                flowMode = .camera
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Measure Me will use the camera to analyse body shape on this iPhone to estimate measurements. Photos are not uploaded and are discarded after analysis unless you choose to save them.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}

@MainActor
struct MeasurementSummaryRow: View {
    let value: MeasurementValue
    let unit: LengthUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(value.kind.displayName)
                SourceBadge(source: value.source)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(unit.format(centimetres: value.valueCM)).font(.body.monospacedDigit().weight(.semibold))
                if value.source == .cameraEstimate {
                    ConfidenceBadge(confidence: value.confidence)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

@MainActor
struct SessionDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let profileID: UUID
    let sessionID: UUID

    @State private var errorMessage: String?

    var body: some View {
        if let profile = model.profile(id: profileID), let session = profile.sessions.first(where: { $0.id == sessionID }) {
            List {
                Section {
                    LabeledContent("Date", value: session.date.formatted(date: .long, time: .shortened))
                    LabeledContent("Method", value: session.method.displayName)
                    if let c = session.category { LabeledContent("Category", value: c.displayName) }
                }
                if let summary = session.captureSummary {
                    Section("Capture") {
                        LabeledContent("Views", value: summary.viewsCaptured.joined(separator: ", "))
                        LabeledContent("Camera", value: summary.lensDescription)
                        LabeledContent("Depth used", value: summary.usedDepth ? "Yes (LiDAR)" : "No")
                        LabeledContent("Frame quality", value: "\(Int(summary.overallQuality * 100))%")
                        ForEach(summary.notes, id: \.self) { Text($0).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section("Measurements") {
                    ForEach(session.measurements.sorted) { v in
                        VStack(alignment: .leading, spacing: 4) {
                            MeasurementSummaryRow(value: v, unit: profile.preferredUnit)
                            if v.source != .manual {
                                Text("Estimated \(profile.preferredUnit.formatUncertainty(centimetres: v.uncertaintyCM))\(v.originalCameraValueCM.map { ". Original camera estimate: \(profile.preferredUnit.format(centimetres: $0))" } ?? "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let m = v.method { Text(m).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                if !session.savedPhotoFiles.isEmpty {
                    Section("Saved capture photos") {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(session.savedPhotoFiles, id: \.self) { file in
                                    if let image = UIImage(contentsOfFile: model.photoStore.url(sessionID: session.id, fileName: file).path) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(height: 160)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .accessibilityLabel("Saved capture photo \(file)")
                                    }
                                }
                            }
                        }
                        Button("Delete these photos", role: .destructive) {
                            do { try model.deleteCapturePhotos(sessionID: session.id, profileID: profileID) } catch { errorMessage = error.localizedDescription }
                        }
                    }
                }
                Section {
                    Button("Delete this session", role: .destructive) {
                        do {
                            try model.deleteSession(session.id, from: profileID)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("Session deleted", systemImage: "trash")
        }
    }
}
