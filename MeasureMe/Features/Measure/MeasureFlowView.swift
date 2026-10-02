import SwiftUI
import MeasureMeCore

/// Container for one measuring session (camera or manual).
struct MeasureFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var flow: MeasureFlowModel

    init(profile: PersonProfile, mode: MeasureFlowMode) {
        _flow = State(initialValue: MeasureFlowModel(profile: profile, mode: mode))
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            CategorySelectionView(flow: flow, onClose: close)
                .navigationDestination(for: MeasureStep.self) { step in
                    switch step {
                    case .setup: CaptureSetupView(flow: flow)
                    case .capture: CaptureScreen(flow: flow)
                    case .review: CaptureReviewView(flow: flow)
                    case .results: MeasurementResultsView(flow: flow, onDone: close)
                    }
                }
        }
        .onDisappear { flow.discardImages() }
    }

    private func close() {
        flow.discardImages()
        dismiss()
    }
}
