import Foundation

extension MeasurementKind: CodingKeyRepresentable {}

/// Which chart line a size chart belongs to. Selected by the user — never inferred from images.
public enum SizeAudience: String, Codable, CaseIterable, Identifiable, Sendable {
    case unisex
    case womens
    case mens

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unisex: return "Unisex / gender-neutral"
        case .womens: return "Womenswear"
        case .mens: return "Menswear"
        }
    }
}

/// Region a size system belongs to. Size labels with the same name can mean different things per region.
public enum SizeRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    case international
    case us
    case uk
    case eu
    case jp
    case au
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .international: return "International"
        case .us: return "United States"
        case .uk: return "United Kingdom"
        case .eu: return "European Union"
        case .jp: return "Japan"
        case .au: return "Australia / NZ"
        case .other: return "Other"
        }
    }
}

/// Whether the chart describes the wearer's body or the finished garment.
public enum ChartMeasurementType: String, Codable, CaseIterable, Sendable {
    /// "Fits a body with chest 96–100 cm" — compare directly with body measurements.
    case body
    /// "The garment's chest measures 108 cm" — body measurement plus wearing ease must be compared.
    case garment

    public var displayName: String {
        switch self {
        case .body: return "Body measurements"
        case .garment: return "Garment measurements"
        }
    }

    public var explanation: String {
        switch self {
        case .body:
            return "This chart lists the body measurements each size is designed to fit. Your measurements are compared directly."
        case .garment:
            return "This chart lists measurements of the clothing itself. Clothes are bigger than the body, so we add typical wearing ease for your chosen fit before comparing. Ease values are general guidance, not brand data."
        }
    }
}

/// How garment girths are written in a garment chart.
public enum GarmentMeasurementConvention: String, Codable, CaseIterable, Sendable {
    /// Full circumference of the garment.
    case fullCircumference
    /// Garment laid flat, measured across one side (multiply by 2 for the circumference).
    case flatHalfWidth

    public var displayName: String {
        switch self {
        case .fullCircumference: return "Full circumference"
        case .flatHalfWidth: return "Laid flat (half width)"
        }
    }
}

/// A closed range of centimetres. `min == max` represents a single point value (common in garment charts).
public struct MeasurementRange: Codable, Equatable, Sendable {
    public var minCM: Double
    public var maxCM: Double

    public init(minCM: Double, maxCM: Double) {
        self.minCM = Swift.min(minCM, maxCM)
        self.maxCM = Swift.max(minCM, maxCM)
    }

    public init(pointCM: Double) {
        self.init(minCM: pointCM, maxCM: pointCM)
    }

    public var width: Double { maxCM - minCM }
    public var midpoint: Double { (minCM + maxCM) / 2 }
    public var isPoint: Bool { width < 0.0001 }

    public func contains(_ cm: Double) -> Bool { cm >= minCM && cm <= maxCM }

    /// Distance from the value to the nearest edge (0 when inside).
    public func distance(to cm: Double) -> Double {
        if cm < minCM { return minCM - cm }
        if cm > maxCM { return cm - maxCM }
        return 0
    }

    /// Position of a value inside the range, 0 (bottom) … 1 (top). Nil for point ranges.
    public func position(of cm: Double) -> Double? {
        guard !isPoint else { return nil }
        return (cm - minCM) / width
    }

    public func shifted(by deltaCM: Double) -> MeasurementRange {
        MeasurementRange(minCM: minCM + deltaCM, maxCM: maxCM + deltaCM)
    }

    public func scaled(by factor: Double) -> MeasurementRange {
        MeasurementRange(minCM: minCM * factor, maxCM: maxCM * factor)
    }

    /// Whether this range and an interval [lo, hi] overlap.
    public func overlaps(lo: Double, hi: Double) -> Bool { lo <= maxCM && hi >= minCM }

    public func formatted(in unit: LengthUnit) -> String {
        if isPoint { return unit.format(centimetres: minCM) }
        return "\(unit.format(centimetres: minCM, includeSymbol: false))–\(unit.format(centimetres: maxCM))"
    }
}

/// One size in a chart (e.g. "M", "EU 40", "W32 L32").
public struct SizeEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: String { label }
    public var label: String
    public var measurements: [MeasurementKind: MeasurementRange]

    public init(label: String, measurements: [MeasurementKind: MeasurementRange]) {
        self.label = label
        self.measurements = measurements
    }
}

/// Where a chart came from and how trustworthy it is.
public struct ChartSource: Codable, Equatable, Sendable {
    /// Official brand page the chart was copied from. Required for non-demo charts.
    public var url: URL?
    /// When someone last checked the chart against the official source. Required for non-demo charts.
    public var lastVerified: Date?
    /// True for the bundled sample charts. Demo charts are fictional and must never be presented as real brand data.
    public var isDemoData: Bool
    public var notes: String?

    public init(url: URL?, lastVerified: Date?, isDemoData: Bool, notes: String? = nil) {
        self.url = url
        self.lastVerified = lastVerified
        self.isDemoData = isDemoData
        self.notes = notes
    }
}

/// A brand size chart, stored as data. Charts can be specific to a product line, collection or single garment.
public struct SizeChart: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var brand: String
    /// Optional product line, collection, fit name or individual garment this chart applies to.
    public var productLine: String?
    public var category: ClothingCategory
    public var audience: SizeAudience
    public var region: SizeRegion
    /// Name of the size system, e.g. "Letter (XS–XXL)", "EU numeric", "Waist × length".
    public var sizeSystem: String
    public var measurementType: ChartMeasurementType
    /// Only meaningful for garment charts.
    public var garmentConvention: GarmentMeasurementConvention?
    /// Sizes ordered from smallest to largest. Ranges are stored in centimetres.
    public var sizes: [SizeEntry]
    public var source: ChartSource

    public init(id: UUID = UUID(), brand: String, productLine: String? = nil, category: ClothingCategory,
                audience: SizeAudience, region: SizeRegion, sizeSystem: String,
                measurementType: ChartMeasurementType, garmentConvention: GarmentMeasurementConvention? = nil,
                sizes: [SizeEntry], source: ChartSource) {
        self.id = id
        self.brand = brand
        self.productLine = productLine
        self.category = category
        self.audience = audience
        self.region = region
        self.sizeSystem = sizeSystem
        self.measurementType = measurementType
        self.garmentConvention = garmentConvention
        self.sizes = sizes
        self.source = source
    }

    /// Measurement kinds that at least one size in the chart describes.
    public var coveredMeasurements: Set<MeasurementKind> {
        Set(sizes.flatMap { $0.measurements.keys })
    }

    public var displayTitle: String {
        var parts = [brand]
        if let p = productLine, !p.isEmpty { parts.append(p) }
        parts.append(category.displayName)
        return parts.joined(separator: " · ")
    }

    public var subtitle: String {
        "\(audience.displayName) · \(region.displayName) · \(sizeSystem)"
    }

    /// A short trust label for UI: demo, verified (with date) or unverified.
    public var trustLabel: String {
        if source.isDemoData { return "DEMO DATA — fictional, not a real brand chart" }
        if let date = source.lastVerified {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            f.locale = Locale(identifier: "en_US_POSIX")
            return "From official source · last verified \(f.string(from: date))"
        }
        return "Unverified chart"
    }

    /// The range as a *body* range for a given size and measurement: garment charts are converted by
    /// doubling flat widths and subtracting wearing ease for the fit preference.
    public func bodyEquivalentRange(for kind: MeasurementKind, in size: SizeEntry, fit: FitPreference) -> MeasurementRange? {
        guard let range = size.measurements[kind] else { return nil }
        switch measurementType {
        case .body:
            return range
        case .garment:
            var r = range
            if kind.isCircumference, garmentConvention == .flatHalfWidth {
                r = r.scaled(by: 2)
            }
            let ease = EaseGuidelines.easeCM(category: category, kind: kind, fit: fit)
            return r.shifted(by: -ease)
        }
    }
}
