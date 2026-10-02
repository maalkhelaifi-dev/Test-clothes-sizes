import Foundation

/// Typical wearing ease (garment measurement minus body measurement), used ONLY to compare body
/// measurements with *garment* charts.
///
/// These are general pattern-making rules of thumb, not data from any brand. Real ease varies by
/// fabric (stretch vs. woven), style and brand. The UI states this whenever a garment chart is used.
public enum EaseGuidelines {

    public static let disclaimer =
        "Wearing ease values are general guidance for woven garments, not brand data. Stretch fabrics need less ease."

    /// Ease in centimetres to add to a body measurement to get the expected garment measurement.
    public static func easeCM(category: ClothingCategory, kind: MeasurementKind, fit: FitPreference) -> Double {
        let (slim, regular, relaxed) = table(category: category, kind: kind)
        switch fit {
        case .slim: return slim
        case .regular: return regular
        case .relaxed: return relaxed
        }
    }

    private static func table(category: ClothingCategory, kind: MeasurementKind) -> (Double, Double, Double) {
        switch kind {
        case .chest:
            switch category {
            case .tops: return (4, 8, 14)
            case .shirts: return (6, 10, 16)
            case .jackets, .suits: return (8, 12, 16)
            case .outerwear: return (12, 16, 22)
            case .dresses: return (4, 7, 12)
            default: return (6, 10, 14)
            }
        case .waist:
            switch category {
            case .trousers, .skirts: return (0, 2, 4)
            case .dresses: return (2, 4, 8)
            case .suits: return (2, 4, 6)
            default: return (6, 10, 16)
            }
        case .hips:
            switch category {
            case .trousers, .skirts: return (2, 5, 9)
            case .dresses: return (4, 6, 10)
            default: return (6, 10, 16)
            }
        case .neck: return (1, 1.5, 2.5)
        case .bicep: return (3, 5, 8)
        case .thigh: return (2, 5, 9)
        case .knee, .calf: return (2, 5, 9)
        case .shoulderWidth: return (0, 1, 2.5)
        case .sleeveLength, .armLength: return (0, 1, 2)
        case .underbust: return (2, 4, 8)
        case .wrist: return (2, 4, 6)
        case .ankle: return (3, 6, 10)
        // Lengths are generally specified to match the body.
        case .inseam, .outseam, .napeToWaist, .shoulderToWaist, .rise, .height:
            return (0, 0, 0)
        }
    }
}
