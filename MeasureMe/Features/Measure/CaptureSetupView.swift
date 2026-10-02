import SwiftUI
import MeasureMeCore

/// Screen 4 (part 1): how to prepare, device capabilities and capture options.
@MainActor
struct CaptureSetupView: View {
    @Bindable var flow: MeasureFlowModel
    @Environment(AppSettings.self) private var settings
    @State private var capabilities = CameraCapabilities.detect()

    var body: some View {
        @Bindable var settings = settings
        List {
            Section("Before you start") {
                InfoRow(symbol: "tshirt", title: "Wear fitted clothing",
                        text: "Close-fitting clothes such as leggings, cycling shorts and a fitted top. Loose clothes make you look bigger. Tie back long hair.")
                InfoRow(symbol: "shoeprints.fill", title: "Barefoot if possible",
                        text: "Shoes add height and throw off the scale. Your height entry should match how you stand in the photos.")
                InfoRow(symbol: "iphone.gen3", title: "Place the phone upright",
                        text: "Prop the phone upright (portrait) at about waist height, or ask someone to hold it level. Then stand 2–3 m (7–10 ft) away.")
                InfoRow(symbol: "lightbulb", title: "Good, even light",
                        text: "Face a light source. Avoid standing in front of a bright window. A plain wall behind you helps.")
                InfoRow(symbol: "figure.stand", title: "Neutral posture",
                        text: "Stand straight, feet hip-width apart, arms held slightly away from your body, breathing normally.")
            }

            Section {
                ForEach(flow.requiredViews) { view in
                    Label {
                        VStack(alignment: .leading) {
                            Text(view.displayName).font(.headline)
                            Text(view.instruction).font(.subheadline).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: view == .side ? "person.fill.turn.right" : "person.fill")
                    }
                }
                Toggle("Add a back view", isOn: $flow.includeBackView)
            } header: {
                Text("Photos we’ll take")
            } footer: {
                Text("A single front photo can’t measure girths like chest or waist, so a side view is always needed. A back view helps cross-check widths.")
            }

            Section {
                if capabilities.hasFrontCamera {
                    Toggle("Use front camera instead", isOn: $flow.useFrontCamera)
                }
                if flow.useFrontCamera {
                    Label("The front camera has a wider, more distorted lens and is usually lower quality. Results will be less accurate.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if capabilities.hasLiDARDepthCamera && !flow.useFrontCamera {
                    Toggle("Use LiDAR depth as a cross-check", isOn: $settings.useDepthWhenAvailable)
                }
                Toggle("Spoken guidance", isOn: $settings.voiceGuidance)
                DisclosureGroup("This iPhone’s camera features") {
                    ForEach(capabilities.rows) { row in
                        HStack(alignment: .top) {
                            Image(systemName: row.available ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(row.available ? .green : .secondary)
                                .accessibilityLabel(row.available ? "Available" : "Not available")
                            VStack(alignment: .leading) {
                                Text(row.name)
                                Text(row.usage).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Camera")
            }

            Section {
                Label("Frames are analysed on this iPhone and discarded afterwards\(settings.saveCapturePhotos ? ", except the photos you chose to save in Settings" : ""). Nothing is uploaded.", systemImage: "lock")
                    .font(.footnote)
                Button("Start camera") {
                    flow.pendingViews = flow.requiredViews
                    flow.path.append(.capture)
                }
                .buttonStyle(.primary)
                .disabled(!capabilities.canCapture && !capabilities.isSimulator)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if !capabilities.canCapture && !capabilities.isSimulator {
                    Text("No camera was found. You can still enter measurements manually.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Camera setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}
