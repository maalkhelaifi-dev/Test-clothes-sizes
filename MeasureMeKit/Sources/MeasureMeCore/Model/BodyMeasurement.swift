import Foundation

/// Where a measurement value came from.
public enum MeasurementSource: String, Codable, Sendable {
    /// Estimated by the camera pipeline and not changed by the user.
    case cameraEstimate
    /// Estimated by the camera, then corrected by the user.
    case cameraEdited
    /// Typed in by the user (e.g. from a tape measure).
    case manual

    public var displayName: String {
        switch self {
        case .cameraEstimate: return "Camera estimate"
        case .cameraEdited: return "Camera estimate, edited"
        case .manual: return "Entered manually"
        }
    }
}

/// How much a value can be trusted.
public enum ConfidenceLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case low
    case medium
    case high

    private var order: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    public static func < (lhs: ConfidenceLevel, rhs: ConfidenceLevel) -> Bool { lhs.order < rhs.order }

    public var displayName: String {
        switch self {
        case .low: return "Low confidence"
        case .medium: return "Medium confidence"
        case .high: return "High confidence"
        }
    }

    /// Lower one step (never below `.low`).
    public func lowered(by steps: Int = 1) -> ConfidenceLevel {
        let all: [ConfidenceLevel] = [.low, .medium, .high]
        return all[max(0, order - steps)]
    }
}

/// One stored body measurement.
public struct MeasurementValue: Codable, Equatable, Identifiable, Sendable {
    public var id: MeasurementKind { kind }
    public var kind: MeasurementKind
    /// Canonical value in centimetres.
    public var valueCM: Double
    public var source: MeasurementSource
    public var confidence: ConfidenceLevel
    /// Estimated ± uncertainty in centimetres (≈ one standard deviation).
    public var uncertaintyCM: Double
    public var capturedAt: Date
    /// Short description of how the value was obtained (shown to the user).
    public var method: String?
    /// The original camera estimate, kept when the user edits a value so they can revert.
    public var originalCameraValueCM: Double?

    public init(
        kind: MeasurementKind,
        valueCM: Double,
        source: MeasurementSource,
        confidence: ConfidenceLevel,
        uncertaintyCM: Double,
        capturedAt: Date = Date(),
        method: String? = nil,
        originalCameraValueCM: Double? = nil
    ) {
        self.kind = kind
        self.valueCM = valueCM
        self.source = source
        self.confidence = confidence
        self.uncertaintyCM = uncertaintyCM
        self.capturedAt = capturedAt
        self.method = method
        self.originalCameraValueCM = originalCameraValueCM
    }

    /// Default uncertainty assumed for a careful tape-measure reading.
    public static let manualUncertaintyCM = 1.0

    /// Creates a manually entered value (treated as high confidence).
    public static func manual(_ kind: MeasurementKind, cm: Double, at date: Date = Date()) -> MeasurementValue {
        MeasurementValue(kind: kind, valueCM: cm, source: .manual, confidence: .high,
                         uncertaintyCM: manualUncertaintyCM, capturedAt: date, method: "Tape measure (entered by you)")
    }

    /// Returns a copy with a user correction applied. Camera-sourced values keep their original estimate.
    public func edited(toCM newValue: Double, at date: Date = Date()) -> MeasurementValue {
        var copy = self
        switch source {
        case .cameraEstimate, .cameraEdited:
            copy.originalCameraValueCM = originalCameraValueCM ?? valueCM
            copy.source = .cameraEdited
        case .manual:
            break
        }
        copy.valueCM = newValue
        // A user correction is assumed to come from a tape measure.
        copy.confidence = .high
        copy.uncertaintyCM = Self.manualUncertaintyCM
        copy.capturedAt = date
        return copy
    }

    /// Returns the value in the requested unit.
    public func value(in unit: LengthUnit) -> Double { unit.fromCentimetres(valueCM) }
}

/// A collection of measurements keyed by kind.
public struct MeasurementSet: Codable, Equatable, Sendable {
    public private(set) var values: [MeasurementKind: MeasurementValue]

    public init(_ values: [MeasurementValue] = []) {
        var dict: [MeasurementKind: MeasurementValue] = [:]
        for v in values { dict[v.kind] = v }
        self.values = dict
    }

    public subscript(kind: MeasurementKind) -> MeasurementValue? {
        get { values[kind] }
        set { values[kind] = newValue.map { v in var v = v; v.kind = kind; return v } }
    }

    public var isEmpty: Bool { values.isEmpty }

    public var sorted: [MeasurementValue] {
        MeasurementKind.allCases.compactMap { values[$0] }
    }

    public mutating func remove(_ kind: MeasurementKind) { values[kind] = nil }

    /// Merges `other` on top of this set. Values in `other` win.
    public func merging(_ other: MeasurementSet) -> MeasurementSet {
        var copy = self
        for (k, v) in other.values { copy.values[k] = v }
        return copy
    }

    // Codable as an array for a stable, readable JSON form.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(try c.decode([MeasurementValue].self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(sorted)
    }
}
