import SwiftUI
import MeasureMeCore

/// Screen 3: clothing category, fit preference and which measurements to capture.
@MainActor
struct CategorySelectionView: View {
    @Bindable var flow: MeasureFlowModel
    let onClose: () -> Void
    @State private var showOther = false

    private var relevant: [MeasurementKind] {
        (flow.category.primaryMeasurements + flow.category.secondaryMeasurements).filter { $0 != .height }
    }

    private var others: [MeasurementKind] {
        MeasurementKind.allCases.filter { $0 != .height && !relevant.contains($0) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Category", selection: $flow.category) {
                    ForEach(ClothingCategory.allCases) { c in
                        Label(c.displayName, systemImage: c.systemImage).tag(c)
                    }
                }
                .pickerStyle(.navigationLink)
            } header: {
                Text("What are you shopping for?")
            }

            Section {
                Picker("Fit", selection: $flow.fit) {
                    ForEach(FitPreference.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(flow.fit.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Preferred fit")
            }

            Section {
                ForEach(relevant, id: \.self) { kind in
                    kindToggle(kind, isPrimary: flow.category.primaryMeasurements.contains(kind))
                }
                DisclosureGroup("Other measurements", isExpanded: $showOther) {
                    ForEach(others, id: \.self) { kindToggle($0, isPrimary: false) }
                }
            } header: {
                Text("Measurements to capture")
            } footer: {
                Text("Measurements marked “key” decide the size for \(flow.category.displayName.lowercased()). Some measurements can only be entered by hand — they’re marked with a ruler.")
            }

            Section {
                Button(flow.mode == .camera ? "Continue to camera setup" : "Continue to manual entry") {
                    if flow.mode == .camera {
                        flow.pendingViews = flow.requiredViews
                        flow.path.append(.setup)
                    } else {
                        flow.startManualEntry()
                        flow.path.append(.results)
                    }
                }
                .buttonStyle(.primary)
                .disabled(flow.selectedKinds.isEmpty)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(flow.mode == .camera ? "Measure with camera" : "Enter measurements")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
    }

    private func kindToggle(_ kind: MeasurementKind, isPrimary: Bool) -> some View {
        Toggle(isOn: Binding(
            get: { flow.selectedKinds.contains(kind) },
            set: { on in if on { flow.selectedKinds.insert(kind) } else { flow.selectedKinds.remove(kind) } }
        )) {
            HStack {
                Text(kind.displayName)
                if isPrimary {
                    Text("key")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                if flow.mode == .camera && kind.cameraSupport == .manualOnly {
                    Image(systemName: "ruler")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Manual entry only")
                }
            }
        }
    }
}
