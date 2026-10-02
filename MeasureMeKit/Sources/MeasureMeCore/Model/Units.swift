import Foundation

/// Length units supported by the app. All values are stored internally in centimetres;
/// conversion happens only at the edges (display, input, chart import).
public enum LengthUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case centimetres = "cm"
    case inches = "in"

    public var id: String { rawValue }

    public static let centimetresPerInch = 2.54

    public var symbol: String { rawValue }

    public var displayName: String {
        switch self {
        case .centimetres: return "Centimetres (cm)"
        case .inches: return "Inches (in)"
        }
    }

    /// Converts a value in this unit to centimetres.
    public func toCentimetres(_ value: Double) -> Double {
        switch self {
        case .centimetres: return value
        case .inches: return value * Self.centimetresPerInch
        }
    }

    /// Converts a value in centimetres to this unit.
    public func fromCentimetres(_ cm: Double) -> Double {
        switch self {
        case .centimetres: return cm
        case .inches: return cm / Self.centimetresPerInch
        }
    }

    /// Converts a value from one unit to another.
    public static func convert(_ value: Double, from: LengthUnit, to: LengthUnit) -> Double {
        to.fromCentimetres(from.toCentimetres(value))
    }

    /// Rounding step used when presenting values (0.5 cm or 0.25 in).
    public var displayStep: Double {
        switch self {
        case .centimetres: return 0.5
        case .inches: return 0.25
        }
    }

    /// Rounds a value expressed in this unit to the display step.
    public func roundedForDisplay(_ value: Double) -> Double {
        (value / displayStep).rounded() * displayStep
    }

    /// Formats a centimetre value in this unit, e.g. "92.5 cm" or "36.5 in".
    public func format(centimetres cm: Double, includeSymbol: Bool = true) -> String {
        let v = roundedForDisplay(fromCentimetres(cm))
        let text: String
        if v == v.rounded() {
            text = String(format: "%.0f", v)
        } else if self == .inches {
            text = String(format: "%.2f", v).replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
        } else {
            text = String(format: "%.1f", v)
        }
        return includeSymbol ? "\(text) \(symbol)" : text
    }

    /// Formats a ± uncertainty in this unit, e.g. "±2 cm".
    public func formatUncertainty(centimetres cm: Double) -> String {
        "±" + format(centimetres: max(cm, 0))
    }

    /// Parses user input in this unit. Accepts "," as decimal separator.
    /// Returns centimetres, or nil when the text is not a finite positive number.
    public func parseToCentimetres(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: symbol, with: "")
            .trimmingCharacters(in: .whitespaces)
        guard let v = Double(cleaned), v.isFinite, v > 0 else { return nil }
        return toCentimetres(v)
    }
}

/// Imperial height helper (feet + inches).
public struct FeetInches: Equatable, Sendable {
    public var feet: Int
    public var inches: Double

    public init(feet: Int, inches: Double) {
        self.feet = feet
        self.inches = inches
    }

    public init(centimetres cm: Double) {
        let totalInches = cm / LengthUnit.centimetresPerInch
        var f = Int(totalInches / 12)
        var i = (totalInches - Double(f) * 12).rounded()
        if i >= 12 { f += 1; i -= 12 }
        self.feet = f
        self.inches = i
    }

    public var centimetres: Double {
        (Double(feet) * 12 + inches) * LengthUnit.centimetresPerInch
    }
}
