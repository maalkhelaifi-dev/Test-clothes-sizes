import Foundation

/// Clothing categories and the body measurements each one needs.
public enum ClothingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case tops        // T-shirts, knitwear, casual tops
    case shirts      // Collared shirts
    case jackets     // Blazers, light jackets
    case outerwear   // Coats, parkas
    case suits
    case trousers    // Trousers, jeans, shorts
    case skirts
    case dresses

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tops: return "Tops & knitwear"
        case .shirts: return "Shirts"
        case .jackets: return "Jackets & blazers"
        case .outerwear: return "Coats & outerwear"
        case .suits: return "Suits"
        case .trousers: return "Trousers & jeans"
        case .skirts: return "Skirts"
        case .dresses: return "Dresses"
        }
    }

    public var systemImage: String {
        switch self {
        case .tops: return "tshirt"
        case .shirts: return "tshirt.fill"
        case .jackets: return "figure.stand"
        case .outerwear: return "cloud.snow"
        case .suits: return "briefcase"
        case .trousers: return "figure.walk"
        case .skirts: return "triangle"
        case .dresses: return "figure.dress.line.vertical.figure"
        }
    }

    /// Measurements that normally decide the size for this category.
    public var primaryMeasurements: [MeasurementKind] {
        switch self {
        case .tops: return [.chest]
        case .shirts: return [.chest, .neck]
        case .jackets: return [.chest]
        case .outerwear: return [.chest]
        case .suits: return [.chest, .waist]
        case .trousers: return [.waist, .hips]
        case .skirts: return [.waist, .hips]
        case .dresses: return [.chest, .waist, .hips]
        }
    }

    /// Measurements that refine fit or length when the chart provides them.
    public var secondaryMeasurements: [MeasurementKind] {
        switch self {
        case .tops: return [.waist, .shoulderWidth, .armLength]
        case .shirts: return [.sleeveLength, .waist, .shoulderWidth]
        case .jackets: return [.shoulderWidth, .sleeveLength, .waist]
        case .outerwear: return [.shoulderWidth, .sleeveLength, .hips]
        case .suits: return [.shoulderWidth, .sleeveLength, .inseam, .hips]
        case .trousers: return [.inseam, .thigh, .outseam, .rise]
        case .skirts: return [.outseam]
        case .dresses: return [.underbust, .shoulderWidth, .napeToWaist, .shoulderToWaist]
        }
    }

    /// Everything relevant for the category (primary first). Height is always included as the scale reference.
    public var relevantMeasurements: [MeasurementKind] {
        [.height] + primaryMeasurements + secondaryMeasurements
    }

    /// Relative importance of a measurement in recommendations for this category.
    public func weight(for kind: MeasurementKind) -> Double {
        if primaryMeasurements.contains(kind) { return 1.0 }
        if secondaryMeasurements.contains(kind) { return 0.5 }
        return 0.25
    }

    /// Whether this category needs a side view (true whenever a girth is primary).
    public var needsSideView: Bool {
        primaryMeasurements.contains { $0.isCircumference }
    }
}

/// How the user prefers clothes to fit.
public enum FitPreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case slim
    case regular
    case relaxed

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .slim: return "Slim"
        case .regular: return "Regular"
        case .relaxed: return "Relaxed"
        }
    }

    public var explanation: String {
        switch self {
        case .slim: return "Close to the body. When between sizes, we lean towards the smaller size."
        case .regular: return "Standard fit with normal room to move."
        case .relaxed: return "Roomier fit. When between sizes, we lean towards the larger size."
        }
    }

    /// Where, within a body-chart size range, the user's measurement ideally sits (0 = bottom, 1 = top).
    /// Slim → user near the top of the range (snugger); relaxed → near the bottom (roomier).
    public var targetPositionInRange: Double {
        switch self {
        case .slim: return 0.7
        case .regular: return 0.5
        case .relaxed: return 0.3
        }
    }
}
