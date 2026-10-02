import Foundation

/// How a user's measurement sits relative to a size's range.
public enum RangeStatus: String, Sendable {
    case below
    case within
    case above

    public var displayName: String {
        switch self {
        case .below: return "Below range"
        case .within: return "Within range"
        case .above: return "Above range"
        }
    }
}

/// The user's measurement next to one size's range for one measurement kind.
public struct MeasurementComparison: Equatable, Identifiable, Sendable {
    public var id: MeasurementKind { kind }
    public let kind: MeasurementKind
    public let userValueCM: Double
    public let userUncertaintyCM: Double
    public let userConfidence: ConfidenceLevel
    public let userSource: MeasurementSource
    /// The range exactly as listed in the chart (body or garment measurement).
    public let chartRange: MeasurementRange
    /// The range expressed as body measurements (same as `chartRange` for body charts).
    public let bodyRange: MeasurementRange
    public let status: RangeStatus
    /// Signed distance outside the body range: negative when below, positive when above, 0 when within.
    public let differenceCM: Double
    public let weight: Double
    /// The size this measurement would pick on its own.
    public let individuallyPreferredSize: String?
}

/// Per-size score (lower is better).
public struct SizeScore: Equatable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let score: Double
    public let comparisons: [MeasurementComparison]
}

public struct SizeRecommendation: Equatable, Sendable {
    public let chartID: UUID
    public let chartType: ChartMeasurementType
    public let isDemoChart: Bool
    public let fit: FitPreference
    public let size: String
    public let comparisons: [MeasurementComparison]
    /// A second size to consider when the call is close.
    public let alternativeSize: String?
    public let alternativeReason: String?
    public let alternativeComparisons: [MeasurementComparison]
    /// Measurements that decided the recommendation.
    public let drivingMeasurements: [MeasurementKind]
    /// Measurements that, on their own, point to a different size.
    public let conflictingMeasurements: [MeasurementKind]
    public let confidence: ConfidenceLevel
    public let explanation: [String]
    public let scores: [SizeScore]
}

public enum RecommendationOutcome: Equatable, Sendable {
    case recommended(SizeRecommendation)
    /// The chart or the user's data is missing what is needed. No size is suggested.
    case insufficientData(reasons: [String], missingMeasurements: [MeasurementKind])
    /// The user's measurements are well outside every size in the chart.
    case outsideChartRange(nearestSize: String, comparisons: [MeasurementComparison], explanation: [String])
}

/// Maps body measurements onto a size chart.
///
/// Algorithm (per size): for every measurement both the chart and the user have, compute a cost:
/// inside the range → small cost depending on where in the range the user sits relative to the fit preference;
/// outside → 0.5 + distance / tolerance. Costs are weighted by how important the measurement is for
/// the category (primary 1.0, secondary 0.5, other 0.25). The lowest weighted mean wins. An adjacent size is
/// offered as an alternative when its score is close or the user's measurement uncertainty overlaps it.
public enum SizeRecommender {

    public static let closeScoreMargin = 0.2

    public static func tolerance(for kind: MeasurementKind) -> Double {
        kind.isCircumference ? 3.0 : 2.0
    }

    public static func recommend(chart: SizeChart, measurements: MeasurementSet, fit: FitPreference) -> RecommendationOutcome {
        let category = chart.category
        let covered = chart.coveredMeasurements
        let primaryCovered = category.primaryMeasurements.filter { covered.contains($0) }

        guard !chart.sizes.isEmpty else {
            return .insufficientData(reasons: ["This chart has no sizes."], missingMeasurements: [])
        }
        guard !primaryCovered.isEmpty else {
            let names = category.primaryMeasurements.map { $0.displayName.lowercased() }.joined(separator: " or ")
            return .insufficientData(
                reasons: ["This chart does not list \(names), which are needed to size \(category.displayName.lowercased()). No size can be recommended from it."],
                missingMeasurements: [])
        }
        let missing = primaryCovered.filter { measurements[$0] == nil }
        if !missing.isEmpty {
            let names = missing.map { $0.displayName.lowercased() }.joined(separator: ", ")
            return .insufficientData(
                reasons: ["Add your \(names) to get a recommendation from this chart."],
                missingMeasurements: missing)
        }

        let usableKinds = MeasurementKind.allCases.filter { covered.contains($0) && measurements[$0] != nil }
        let bodyRanges = bodyRangeTable(chart: chart, fit: fit)
        let target = chart.measurementType == .body ? fit.targetPositionInRange : 0.5

        func cost(_ kind: MeasurementKind, _ range: MeasurementRange, _ value: Double) -> Double {
            let d = range.distance(to: value)
            if d == 0 {
                let pos = range.position(of: value) ?? 0.5
                return abs(pos - target) * 0.5
            }
            // Outside the range: slim fits tolerate a size that is a little small, relaxed fits one that is a
            // little big. This is what lets fit preference decide when a value falls between two sizes.
            var asymmetry = 1.0
            if chart.measurementType == .body {
                let sizeIsSmall = value > range.maxCM
                switch fit {
                case .slim: asymmetry = sizeIsSmall ? 0.7 : 1.3
                case .relaxed: asymmetry = sizeIsSmall ? 1.3 : 0.7
                case .regular: asymmetry = 1.0
                }
            }
            return 0.5 + d * asymmetry / tolerance(for: kind)
        }

        // Individual preference per measurement.
        var preferred: [MeasurementKind: String] = [:]
        for kind in usableKinds {
            let value = measurements[kind]!.valueCM
            var best: (String, Double)?
            for size in chart.sizes {
                guard let r = bodyRanges[size.label]?[kind] else { continue }
                let c = cost(kind, r, value)
                if best == nil || c < best!.1 { best = (size.label, c) }
            }
            preferred[kind] = best?.0
        }

        func comparisons(for size: SizeEntry) -> [MeasurementComparison] {
            usableKinds.compactMap { kind in
                guard let r = bodyRanges[size.label]?[kind], let chartRange = size.measurements[kind], let m = measurements[kind] else { return nil }
                let status: RangeStatus = m.valueCM < r.minCM ? .below : (m.valueCM > r.maxCM ? .above : .within)
                let diff: Double = status == .below ? m.valueCM - r.minCM : (status == .above ? m.valueCM - r.maxCM : 0)
                return MeasurementComparison(kind: kind, userValueCM: m.valueCM, userUncertaintyCM: m.uncertaintyCM,
                                             userConfidence: m.confidence, userSource: m.source,
                                             chartRange: chartRange, bodyRange: r, status: status, differenceCM: diff,
                                             weight: category.weight(for: kind), individuallyPreferredSize: preferred[kind])
            }
        }

        var scores: [SizeScore] = []
        for size in chart.sizes {
            var total = 0.0
            var weights = 0.0
            for kind in usableKinds {
                let w = category.weight(for: kind)
                let value = measurements[kind]!.valueCM
                if let r = bodyRanges[size.label]?[kind] {
                    total += w * cost(kind, r, value)
                } else if primaryCovered.contains(kind) {
                    total += w * 0.75   // size doesn't state a primary measurement: mild penalty
                } else {
                    continue
                }
                weights += w
            }
            let score = weights > 0 ? total / weights : .infinity
            scores.append(SizeScore(label: size.label, score: score, comparisons: comparisons(for: size)))
        }

        let order = Dictionary(uniqueKeysWithValues: chart.sizes.enumerated().map { ($1.label, $0) })
        let ranked = scores.sorted { a, b in
            if abs(a.score - b.score) > 1e-9 { return a.score < b.score }
            return order[a.label]! < order[b.label]!
        }
        guard let best = ranked.first, best.score.isFinite else {
            return .insufficientData(reasons: ["None of the sizes in this chart list the measurements you have."], missingMeasurements: [])
        }
        let bestComparisons = best.comparisons

        // Outside chart: every primary measurement is far outside the best size.
        let primaryComps = bestComparisons.filter { primaryCovered.contains($0.kind) }
        if !primaryComps.isEmpty, primaryComps.allSatisfy({ abs($0.differenceCM) > tolerance(for: $0.kind) * 1.5 }) {
            let isAbove = primaryComps.allSatisfy { $0.status == .above }
            let isBelow = primaryComps.allSatisfy { $0.status == .below }
            var lines = ["Your measurements are outside the range this chart covers."]
            if isAbove { lines.append("They are larger than the largest listed size; the brand may offer extended sizes with a separate chart.") }
            if isBelow { lines.append("They are smaller than the smallest listed size; the brand may offer petite or smaller sizes with a separate chart.") }
            lines.append("Nearest listed size: \(best.label). Check the brand’s fit guidance before buying.")
            return .outsideChartRange(nearestSize: best.label, comparisons: bestComparisons, explanation: lines)
        }

        // Driving and conflicting measurements.
        let maxWeight = usableKinds.map { category.weight(for: $0) }.max() ?? 1
        var driving = usableKinds.filter { preferred[$0] == best.label && category.weight(for: $0) == maxWeight }
        if driving.isEmpty { driving = usableKinds.filter { category.weight(for: $0) == maxWeight } }
        let conflicting = usableKinds.filter { preferred[$0] != nil && preferred[$0] != best.label && category.weight(for: $0) >= 0.5 }

        // Alternative size: adjacent, and close in score or within the user's uncertainty.
        let bestIndex = order[best.label]!
        var alternative: (SizeScore, String)?
        for idx in [bestIndex - 1, bestIndex + 1] where idx >= 0 && idx < chart.sizes.count {
            let label = chart.sizes[idx].label
            guard let s = scores.first(where: { $0.label == label }), s.score.isFinite else { continue }
            var reason: String?
            let direction = idx > bestIndex ? "larger" : "smaller"
            if s.score - best.score < closeScoreMargin {
                reason = "\(label) is almost as good a match. Consider it if you prefer a \(idx > bestIndex ? "roomier" : "closer") fit."
            }
            for kind in usableKinds where category.weight(for: kind) >= 0.5 {
                guard let m = measurements[kind], let r = bodyRanges[label]?[kind] else { continue }
                if r.overlaps(lo: m.valueCM - m.uncertaintyCM, hi: m.valueCM + m.uncertaintyCM) && !r.contains(m.valueCM) {
                    reason = "Your \(kind.displayName.lowercased()) (\(LengthUnit.centimetres.format(centimetres: m.valueCM)) \(LengthUnit.centimetres.formatUncertainty(centimetres: m.uncertaintyCM))) is close enough to the \(direction) size \(label) that measurement uncertainty could change the result."
                    break
                }
            }
            let pointingHere = conflicting.filter { preferred[$0] == label }
            if !pointingHere.isEmpty {
                let names = pointingHere.map { $0.displayName.lowercased() }.joined(separator: " and ")
                reason = "Measured on its own, your \(names) point\(pointingHere.count == 1 ? "s" : "") to \(label), so the best size depends on which area you want to fit best."
            }
            if let reason, alternative == nil || s.score < alternative!.0.score {
                alternative = (s, reason)
            }
        }

        // Confidence.
        var confidence: ConfidenceLevel = .high
        for kind in driving + primaryCovered {
            if let c = measurements[kind]?.confidence, c < confidence { confidence = c }
        }
        if chart.measurementType == .garment { confidence = min(confidence, .medium) }
        if alternative != nil { confidence = min(confidence, .medium) }

        // Explanation.
        var lines: [String] = []
        let drivingNames = driving.map { $0.displayName.lowercased() }.joined(separator: " and ")
        lines.append("Recommended size \(best.label), based mainly on your \(drivingNames).")
        for comp in bestComparisons where comp.weight >= 0.5 {
            let unit = LengthUnit.centimetres
            switch comp.status {
            case .within:
                lines.append("\(comp.kind.displayName): \(unit.format(centimetres: comp.userValueCM)) is within \(best.label) (\(comp.bodyRange.formatted(in: unit)) body).")
            case .below:
                lines.append("\(comp.kind.displayName): \(unit.format(centimetres: comp.userValueCM)) is \(unit.format(centimetres: -comp.differenceCM)) below \(best.label) (\(comp.bodyRange.formatted(in: unit)) body).")
            case .above:
                lines.append("\(comp.kind.displayName): \(unit.format(centimetres: comp.userValueCM)) is \(unit.format(centimetres: comp.differenceCM)) above \(best.label) (\(comp.bodyRange.formatted(in: unit)) body).")
            }
        }
        if chart.measurementType == .garment {
            lines.append("This is a garment chart: we added typical \(fit.displayName.lowercased())-fit wearing ease to your body measurements. \(EaseGuidelines.disclaimer)")
        } else if fit != .regular {
            lines.append("Fit preference “\(fit.displayName)” is applied when you fall between sizes.")
        }
        let lowConfidence = usableKinds.filter { category.weight(for: $0) >= 0.5 && measurements[$0]!.confidence == .low }
        if !lowConfidence.isEmpty {
            lines.append("Low-confidence measurements: \(lowConfidence.map { $0.displayName.lowercased() }.joined(separator: ", ")). Checking them with a tape measure will make this more reliable.")
        }
        if chart.source.isDemoData {
            lines.append("This chart is DEMO DATA for a fictional brand. Do not use it to buy real clothes.")
        }

        return .recommended(SizeRecommendation(
            chartID: chart.id, chartType: chart.measurementType, isDemoChart: chart.source.isDemoData, fit: fit,
            size: best.label, comparisons: bestComparisons,
            alternativeSize: alternative?.0.label, alternativeReason: alternative?.1,
            alternativeComparisons: alternative?.0.comparisons ?? [],
            drivingMeasurements: driving, conflictingMeasurements: conflicting,
            confidence: confidence, explanation: lines, scores: ranked))
    }

    /// Body-equivalent ranges for every size and kind. For garment charts that list single values,
    /// each size is widened to the midpoints between it and its neighbours so "within a size" is meaningful.
    static func bodyRangeTable(chart: SizeChart, fit: FitPreference) -> [String: [MeasurementKind: MeasurementRange]] {
        var table: [String: [MeasurementKind: MeasurementRange]] = [:]
        for size in chart.sizes {
            var row: [MeasurementKind: MeasurementRange] = [:]
            for kind in size.measurements.keys {
                row[kind] = chart.bodyEquivalentRange(for: kind, in: size, fit: fit)
            }
            table[size.label] = row
        }
        for kind in chart.coveredMeasurements {
            let labels = chart.sizes.map(\.label).filter { table[$0]?[kind] != nil }
            let ranges = labels.map { table[$0]![kind]! }
            guard ranges.count > 1, ranges.allSatisfy(\.isPoint) else { continue }
            for (i, label) in labels.enumerated() {
                let p = ranges[i].minCM
                let lowerGap = i > 0 ? (p - ranges[i - 1].minCM) / 2 : (ranges[i + 1].minCM - p) / 2
                let upperGap = i < ranges.count - 1 ? (ranges[i + 1].minCM - p) / 2 : (p - ranges[i - 1].minCM) / 2
                table[label]![kind] = MeasurementRange(minCM: p - abs(lowerGap), maxCM: p + abs(upperGap))
            }
        }
        return table
    }
}
