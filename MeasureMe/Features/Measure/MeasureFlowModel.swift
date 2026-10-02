import Foundation
import Observation
import MeasureMeCore

enum MeasureFlowMode: String, Identifiable {
    case camera
    case manual
    var id: String { rawValue }
}

enum MeasureStep: Hashable {
    case setup
    case capture
    case review
    case results
}

/// State for one measuring session, from category selection to saving.
/// Captured frames live only in this object and are released when the flow closes.
@MainActor
@Observable
final class MeasureFlowModel {
    let profileID: UUID
    let heightCM: Double
    let mode: MeasureFlowMode
    var unit: LengthUnit

    var category: ClothingCategory = .tops {
        didSet { if category != oldValue { selectedKinds = Set(category.primaryMeasurements + category.secondaryMeasurements) } }
    }
    var fit: FitPreference
    var selectedKinds: Set<MeasurementKind>

    // Capture options
    var includeBackView = false
    var useFrontCamera = false

    /// Views the next capture screen should record (all required views, or one view for a retake).
    var pendingViews: [CaptureView] = []

    // Capture results (in memory only)
    var captured: [CaptureView: [CapturedFrame]] = [:]
    var captureLens = ""
    var usedDepth = false

    // Estimation
    var isAnalysing = false
    var estimation: EstimationResult?
    var analysisProblems: [String] = []

    /// Editable measurements shown on the results screen.
    var measurements = MeasurementSet()
    var savedSessionID: UUID?

    var path: [MeasureStep] = []

    init(profile: PersonProfile, mode: MeasureFlowMode) {
        profileID = profile.id
        heightCM = profile.heightCM
        self.mode = mode
        unit = profile.preferredUnit
        fit = profile.defaultFit
        selectedKinds = Set(ClothingCategory.tops.primaryMeasurements + ClothingCategory.tops.secondaryMeasurements)
    }

    /// Measurements to show, in a stable order, height excluded (it comes from the profile).
    var orderedKinds: [MeasurementKind] {
        MeasurementKind.allCases.filter { selectedKinds.contains($0) && $0 != .height }
    }

    var requiredViews: [CaptureView] {
        [.front, .side] + (includeBackView ? [.back] : [])
    }

    var missingViews: [CaptureView] {
        requiredViews.filter { (captured[$0] ?? []).isEmpty }
    }

    var overallQuality: Double {
        let scores = captured.values.flatMap { $0.map(\.qualityScore) }
        return scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
    }

    func merge(captures: [CaptureView: [CapturedFrame]]) {
        for (view, frames) in captures where !frames.isEmpty { captured[view] = frames }
        estimation = nil
    }

    func analyse() async {
        isAnalysing = true
        defer { isAnalysing = false }
        let (result, problems) = await BodyAnalysisService.estimate(frames: captured, heightCM: heightCM, requested: orderedKinds)
        estimation = result
        analysisProblems = problems
        measurements = result.measurementSet()
    }

    func startManualEntry() {
        estimation = nil
        measurements = MeasurementSet()
    }

    /// Drops all frames from memory.
    func discardImages() {
        captured = [:]
    }
}
