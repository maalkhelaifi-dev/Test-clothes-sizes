import Foundation

/// A problem found while validating measurements.
public struct ValidationIssue: Equatable, Sendable, Identifiable {
    public enum Severity: String, Sendable {
        /// The value cannot be accepted (e.g. not a number, impossible for an adult).
        case error
        /// The value is accepted but looks unusual — ask the user to double-check.
        case warning
    }

    public var id: String { "\(kind?.rawValue ?? "general")-\(code)" }
    public let kind: MeasurementKind?
    public let severity: Severity
    public let code: String
    public let message: String

    public init(kind: MeasurementKind?, severity: Severity, code: String, message: String) {
        self.kind = kind
        self.severity = severity
        self.code = code
        self.message = message
    }
}

/// Validates single values and checks a measurement set for internal consistency.
/// Ranges are deliberately wide: the goal is to catch typing/unit mistakes and
/// obviously failed camera estimates, not to judge anyone's body.
public enum MeasurementValidator {

    /// Validates a single value in centimetres.
    public static func validate(_ kind: MeasurementKind, cm: Double) -> [ValidationIssue] {
        guard cm.isFinite, cm > 0 else {
            return [ValidationIssue(kind: kind, severity: .error, code: "notPositive",
                                    message: "\(kind.displayName) must be a positive number.")]
        }
        let range = kind.plausibleRangeCM
        if !range.contains(cm) {
            let unitHint: String
            if range.contains(cm * LengthUnit.centimetresPerInch) {
                unitHint = " It looks like it may have been entered in inches — check the unit."
            } else if range.contains(cm / LengthUnit.centimetresPerInch) {
                unitHint = " It looks like it may have been entered in centimetres while inches were selected."
            } else {
                unitHint = ""
            }
            return [ValidationIssue(
                kind: kind, severity: .error, code: "outOfRange",
                message: "\(kind.displayName) of \(LengthUnit.centimetres.format(centimetres: cm)) is outside the expected adult range (\(Int(range.lowerBound))–\(Int(range.upperBound)) cm).\(unitHint)")]
        }
        return []
    }

    /// Validates a whole set, including relationships between measurements.
    public static func validate(_ set: MeasurementSet) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for v in set.sorted {
            issues += validate(v.kind, cm: v.valueCM)
        }

        func cm(_ k: MeasurementKind) -> Double? { set[k]?.valueCM }

        if let h = cm(.height) {
            if let inseam = cm(.inseam), inseam > h * 0.58 {
                issues.append(.init(kind: .inseam, severity: .warning, code: "inseamVsHeight",
                                    message: "Inseam is unusually long relative to height. Please double-check it."))
            }
            if let outseam = cm(.outseam), outseam > h * 0.72 {
                issues.append(.init(kind: .outseam, severity: .warning, code: "outseamVsHeight",
                                    message: "Outseam is unusually long relative to height. Please double-check it."))
            }
            if let arm = cm(.armLength), arm > h * 0.45 {
                issues.append(.init(kind: .armLength, severity: .warning, code: "armVsHeight",
                                    message: "Arm length is unusually long relative to height. Please double-check it."))
            }
        }
        if let inseam = cm(.inseam), let outseam = cm(.outseam), inseam >= outseam {
            issues.append(.init(kind: .inseam, severity: .warning, code: "inseamVsOutseam",
                                message: "Inseam is usually shorter than outseam. Please double-check both."))
        }
        if let arm = cm(.armLength), let sleeve = cm(.sleeveLength), sleeve <= arm {
            issues.append(.init(kind: .sleeveLength, severity: .warning, code: "sleeveVsArm",
                                message: "Sleeve length (from centre back) is usually longer than arm length."))
        }
        if let under = cm(.underbust), let chest = cm(.chest), under > chest {
            issues.append(.init(kind: .underbust, severity: .warning, code: "underbustVsChest",
                                message: "Underbust is usually smaller than chest/bust. Please double-check both."))
        }
        if let wrist = cm(.wrist), let bicep = cm(.bicep), wrist >= bicep {
            issues.append(.init(kind: .wrist, severity: .warning, code: "wristVsBicep",
                                message: "Wrist is usually smaller than bicep. Please double-check both."))
        }
        if let ankle = cm(.ankle), let calf = cm(.calf), ankle >= calf {
            issues.append(.init(kind: .ankle, severity: .warning, code: "ankleVsCalf",
                                message: "Ankle is usually smaller than calf. Please double-check both."))
        }
        if let thigh = cm(.thigh), let hips = cm(.hips), thigh >= hips {
            issues.append(.init(kind: .thigh, severity: .warning, code: "thighVsHips",
                                message: "Thigh is usually smaller than hips. Please double-check both."))
        }
        return issues
    }

    public static func hasErrors(_ issues: [ValidationIssue]) -> Bool {
        issues.contains { $0.severity == .error }
    }
}
