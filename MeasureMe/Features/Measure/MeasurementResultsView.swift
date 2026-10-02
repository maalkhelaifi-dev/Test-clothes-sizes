import SwiftUI
import MeasureMeCore

/// Screen 6: measurement results with confidence indicators and manual editing.
@MainActor
struct MeasurementResultsView: View {
    @Bindable var flow: MeasureFlowModel
    let onDone: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var errorMessage: String?
    @State private var showAddMore = false

    private var issues: [ValidationIssue] {
        var set = flow.measurements
        set[.height] = .manual(.height, cm: flow.heightCM)
        return MeasurementValidator.validate(set)
    }

    var body: some View {
        List {
            if flow.estimation != nil {
                Section {
                    Label("These are estimates from your photos, not tape-measure results. Check anything marked low confidence, and edit any value you know is different.", systemImage: "info.circle")
                        .font(.subheadline)
                    let warnings = (flow.estimation?.warnings ?? []) + flow.analysisProblems
                    ForEach(warnings, id: \.self) { w in
                        Label(w, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Section {
                    Label("Use a soft tape measure, keep it level and snug but not tight. Tap “How to measure” for each measurement.", systemImage: "ruler")
                        .font(.subheadline)
                }
            }

            Section {
                LabeledContent("Height (from profile)", value: flow.unit.format(centimetres: flow.heightCM))
                Picker("Units", selection: $flow.unit) {
                    ForEach(LengthUnit.allCases) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Section("Measurements") {
                ForEach(flow.orderedKinds, id: \.self) { kind in
                    MeasurementEditRow(
                        kind: kind,
                        unit: flow.unit,
                        estimate: flow.estimation?.estimates[kind],
                        value: Binding(
                            get: { flow.measurements[kind] },
                            set: { flow.measurements[kind] = $0 }
                        ),
                        issues: issues.filter { $0.kind == kind })
                }
                Button("Add another measurement") { showAddMore = true }
            }

            if flow.savedSessionID == nil {
                Section {
                    Button("Save measurements", action: save)
                        .buttonStyle(.primary)
                        .disabled(flow.measurements.isEmpty || MeasurementValidator.hasErrors(issues))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } footer: {
                    if MeasurementValidator.hasErrors(issues) {
                        Text("Fix the values marked in red before saving.").foregroundStyle(.red)
                    } else if settings.saveCapturePhotos && !flow.captured.isEmpty {
                        Text("One photo per view will be saved on this iPhone, as set in Settings. You can delete them from the session’s history.")
                    } else if !flow.captured.isEmpty {
                        Text("Photos will be discarded after saving.")
                    }
                }
            } else {
                Section("Saved") {
                    Label("Measurements saved to this profile’s history.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    NavigationLink {
                        RecommendationView(profileID: flow.profileID, initialCategory: flow.category, initialFit: flow.fit)
                    } label: {
                        Label("Find my size", systemImage: "tag")
                            .font(.headline)
                    }
                    Button("Done", action: onDone)
                }
            }
        }
        .navigationTitle(flow.estimation != nil ? "Your estimates" : "Your measurements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddMore) {
            AddMeasurementSheet(selected: $flow.selectedKinds)
        }
        .alert("Couldn’t save", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func save() {
        var set = MeasurementSet()
        for kind in flow.orderedKinds { if let v = flow.measurements[kind] { set[kind] = v } }
        set[.height] = .manual(.height, cm: flow.heightCM)
        var session = MeasurementSession(
            category: flow.category,
            method: MeasurementSession.inferMethod(for: set),
            measurements: set,
            captureSummary: flow.captured.isEmpty ? nil : CaptureSummary(
                viewsCaptured: flow.requiredViews.filter { flow.captured[$0] != nil }.map(\.displayName),
                usedDepth: flow.usedDepth,
                lensDescription: flow.captureLens,
                overallQuality: flow.overallQuality,
                notes: flow.estimation?.warnings ?? []))
        do {
            if settings.saveCapturePhotos {
                for view in flow.requiredViews {
                    guard let best = flow.captured[view]?.max(by: { $0.qualityScore < $1.qualityScore }),
                          let jpeg = PixelBufferUtils.jpegData(best.pixelBuffer) else { continue }
                    session.savedPhotoFiles.append(try model.photoStore.save(jpeg: jpeg, sessionID: session.id, name: view.rawValue))
                }
            }
            try model.addSession(session, to: flow.profileID)
            flow.savedSessionID = session.id
            flow.discardImages()
        } catch {
            model.photoStore.delete(sessionID: session.id)
            errorMessage = error.localizedDescription
        }
    }
}

/// One editable measurement with its estimate, confidence and how-to-measure help.
@MainActor
struct MeasurementEditRow: View {
    let kind: MeasurementKind
    let unit: LengthUnit
    let estimate: MeasurementEstimate?
    @Binding var value: MeasurementValue?
    let issues: [ValidationIssue]

    @State private var showHelp = false

    private var valueBinding: Binding<Double?> {
        Binding(
            get: { value?.valueCM },
            set: { newValue in
                guard let v = newValue else { value = nil; return }
                if let existing = value {
                    if abs(existing.valueCM - v) > 0.001 { value = existing.edited(toCM: v) }
                } else {
                    value = .manual(kind, cm: v)
                }
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.displayName).font(.headline)
                Spacer()
                LengthField(title: kind.displayName, valueCM: valueBinding, unit: unit)
                    .frame(maxWidth: 140)
            }
            HStack(spacing: 8) {
                if let value {
                    if value.source == .cameraEstimate {
                        ConfidenceBadge(confidence: value.confidence)
                        Text(unit.formatUncertainty(centimetres: value.uncertaintyCM))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Uncertainty plus or minus \(unit.format(centimetres: value.uncertaintyCM))")
                    } else {
                        SourceBadge(source: value.source)
                    }
                    if let original = value.originalCameraValueCM {
                        Button("Revert to \(unit.format(centimetres: original))") {
                            if let est = estimate, let v = est.valueCM {
                                self.value = MeasurementValue(kind: kind, valueCM: v, source: .cameraEstimate, confidence: est.confidence,
                                                              uncertaintyCM: est.uncertaintyCM, method: est.method)
                            }
                        }
                        .font(.caption)
                        .disabled(estimate?.valueCM == nil)
                    }
                } else if let reason = estimate?.unavailableReason {
                    Label("Not estimated", systemImage: "ruler")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Enter a value, or leave blank to skip.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let method = value?.method, value?.source == .cameraEstimate {
                Text(method).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(issues) { issue in
                Label(issue.message, systemImage: issue.severity == .error ? "xmark.octagon" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(issue.severity == .error ? .red : .orange)
            }
            DisclosureGroup("How to measure", isExpanded: $showHelp) {
                Text(kind.howToMeasure).font(.footnote)
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }
}

@MainActor
struct AddMeasurementSheet: View {
    @Binding var selected: Set<MeasurementKind>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(MeasurementKind.Group.allCases, id: \.self) { group in
                    Section(group.rawValue) {
                        ForEach(MeasurementKind.allCases.filter { $0.group == group && $0 != .height }, id: \.self) { kind in
                            Toggle(kind.displayName, isOn: Binding(
                                get: { selected.contains(kind) },
                                set: { on in if on { selected.insert(kind) } else { selected.remove(kind) } }))
                        }
                    }
                }
            }
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
