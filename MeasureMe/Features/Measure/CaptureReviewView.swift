import SwiftUI
import MeasureMeCore

/// Screen 5: capture quality review and retake options.
@MainActor
struct CaptureReviewView: View {
    @Bindable var flow: MeasureFlowModel

    var body: some View {
        List {
            Section {
                Text("Check that each photo shows your whole body from head to feet, in the right pose, with nothing blocking you. Retake any view that doesn’t look right.")
                    .font(.subheadline)
            }
            ForEach(flow.requiredViews) { view in
                Section(view.displayName) {
                    if let frames = flow.captured[view], let best = frames.max(by: { $0.qualityScore < $1.qualityScore }) {
                        HStack(alignment: .top, spacing: 16) {
                            if let image = best.thumbnail {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .accessibilityLabel("\(view.displayName) photo")
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                QualityMeter(score: best.qualityScore)
                                Text("\(frames.count) usable \(frames.count == 1 ? "frame" : "frames")")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                if let depth = best.depthCMPerImagePixel, depth > 0 {
                                    Label("Depth captured", systemImage: "cube.transparent")
                                        .font(.caption)
                                }
                                Button("Retake \(view.displayName.lowercased())") { retake(view) }
                                    .buttonStyle(.bordered)
                            }
                        }
                    } else {
                        Label("Not captured yet", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Button("Capture \(view.displayName.lowercased()) view") { retake(view) }
                            .buttonStyle(.bordered)
                    }
                }
            }

            Section {
                if flow.isAnalysing {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Analysing photos on this iPhone…")
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Button("Estimate measurements") {
                        Task {
                            await flow.analyse()
                            flow.path.append(.results)
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!flow.missingViews.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } footer: {
                Text("Photos stay in memory on this iPhone and are discarded when you finish, unless you turned on photo saving in Settings.")
            }
        }
        .navigationTitle("Review photos")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(flow.isAnalysing)
    }

    private func retake(_ view: CaptureView) {
        flow.pendingViews = [view]
        flow.path.append(.capture)
    }
}

@MainActor
struct QualityMeter: View {
    let score: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Frame quality \(Int((score * 100).rounded()))%")
                .font(.subheadline.weight(.semibold))
            ProgressView(value: score)
                .tint(score >= 0.95 ? .green : (score >= 0.85 ? .orange : .red))
        }
        .accessibilityElement(children: .combine)
    }
}
