import Foundation

/// Problems that prevent a chart from being saved or used.
public enum SizeChartValidationError: Error, Equatable, LocalizedError {
    case missingBrand
    case noSizes
    case duplicateLabel(String)
    case emptySize(String)
    case invalidRange(size: String, kind: MeasurementKind)
    case missingSourceURL
    case missingVerificationDate
    case verificationDateInFuture
    case demoFlagOnUserChart

    public var errorDescription: String? {
        switch self {
        case .missingBrand: return "Enter the brand name."
        case .noSizes: return "Add at least one size."
        case .duplicateLabel(let l): return "The size label “\(l)” is used more than once."
        case .emptySize(let l): return "Size “\(l)” has no measurements."
        case .invalidRange(let s, let k): return "Size “\(s)” has an invalid \(k.displayName.lowercased()) range."
        case .missingSourceURL: return "Add the link to the brand’s official size chart so it can be checked later."
        case .missingVerificationDate: return "Add the date you checked the chart against the official source."
        case .verificationDateInFuture: return "The verification date cannot be in the future."
        case .demoFlagOnUserChart: return "Charts you add cannot be marked as demo data."
        }
    }
}

/// Non-blocking observations about a chart.
public enum SizeChartWarning: Equatable, Sendable {
    case sizesNotIncreasing(MeasurementKind)
    case overlappingRanges(MeasurementKind, String, String)
    case gapBetweenSizes(MeasurementKind, String, String)
}

public enum SizeChartValidator {
    /// Validates a chart. User-added (non-demo) charts must cite an official source URL and verification date —
    /// this is how the app avoids fabricated brand data.
    public static func validate(_ chart: SizeChart, now: Date = Date(), isUserChart: Bool = true) throws {
        guard !chart.brand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SizeChartValidationError.missingBrand }
        guard !chart.sizes.isEmpty else { throw SizeChartValidationError.noSizes }
        var seen = Set<String>()
        for size in chart.sizes {
            let key = size.label.trimmingCharacters(in: .whitespaces).lowercased()
            guard !seen.contains(key) else { throw SizeChartValidationError.duplicateLabel(size.label) }
            seen.insert(key)
            guard !size.measurements.isEmpty else { throw SizeChartValidationError.emptySize(size.label) }
            for (kind, r) in size.measurements {
                guard r.minCM.isFinite, r.maxCM.isFinite, r.minCM > 0, r.maxCM >= r.minCM, r.maxCM < 400 else {
                    throw SizeChartValidationError.invalidRange(size: size.label, kind: kind)
                }
            }
        }
        if isUserChart {
            if chart.source.isDemoData { throw SizeChartValidationError.demoFlagOnUserChart }
            guard chart.source.url != nil else { throw SizeChartValidationError.missingSourceURL }
            guard let verified = chart.source.lastVerified else { throw SizeChartValidationError.missingVerificationDate }
            guard verified <= now.addingTimeInterval(24 * 3600) else { throw SizeChartValidationError.verificationDateInFuture }
        }
    }

    /// Consistency checks between adjacent sizes. These are shown as hints; brand charts do sometimes overlap.
    public static func warnings(for chart: SizeChart) -> [SizeChartWarning] {
        var result: [SizeChartWarning] = []
        for kind in MeasurementKind.allCases where chart.coveredMeasurements.contains(kind) {
            let pairs = chart.sizes.compactMap { s in s.measurements[kind].map { (s.label, $0) } }
            guard pairs.count > 1 else { continue }
            for i in 1..<pairs.count {
                let (prevLabel, prev) = pairs[i - 1]
                let (label, cur) = pairs[i]
                if cur.midpoint < prev.midpoint {
                    result.append(.sizesNotIncreasing(kind))
                } else if cur.minCM < prev.maxCM {
                    result.append(.overlappingRanges(kind, prevLabel, label))
                } else if cur.minCM - prev.maxCM > 2.0, !cur.isPoint {
                    result.append(.gapBetweenSizes(kind, prevLabel, label))
                }
            }
        }
        return result
    }
}

/// Query parameters for finding charts.
public struct SizeChartQuery: Equatable, Sendable {
    public var brand: String?
    public var category: ClothingCategory?
    public var region: SizeRegion?
    public var audience: SizeAudience?
    public var sizeSystem: String?
    public var productLine: String?
    public var includeDemoData: Bool

    public init(brand: String? = nil, category: ClothingCategory? = nil, region: SizeRegion? = nil,
                audience: SizeAudience? = nil, sizeSystem: String? = nil, productLine: String? = nil,
                includeDemoData: Bool = true) {
        self.brand = brand
        self.category = category
        self.region = region
        self.audience = audience
        self.sizeSystem = sizeSystem
        self.productLine = productLine
        self.includeDemoData = includeDemoData
    }
}

/// An in-memory collection of charts with lookup helpers.
public struct SizeChartLibrary: Equatable, Sendable {
    public private(set) var charts: [SizeChart]

    public init(charts: [SizeChart] = []) {
        self.charts = charts
    }

    public mutating func upsert(_ chart: SizeChart) {
        if let i = charts.firstIndex(where: { $0.id == chart.id }) {
            charts[i] = chart
        } else {
            charts.append(chart)
        }
    }

    public mutating func remove(id: UUID) {
        charts.removeAll { $0.id == id }
    }

    public func chart(id: UUID) -> SizeChart? { charts.first { $0.id == id } }

    private static func same(_ a: String?, _ b: String?) -> Bool {
        (a ?? "").trimmingCharacters(in: .whitespaces).caseInsensitiveCompare((b ?? "").trimmingCharacters(in: .whitespaces)) == .orderedSame
    }

    /// Charts matching every non-nil field of the query, sorted with verified charts first,
    /// then product-specific charts before brand-wide ones.
    public func charts(matching q: SizeChartQuery) -> [SizeChart] {
        charts.filter { c in
            (q.includeDemoData || !c.source.isDemoData)
            && (q.brand == nil || Self.same(c.brand, q.brand))
            && (q.category == nil || c.category == q.category)
            && (q.region == nil || c.region == q.region)
            && (q.audience == nil || c.audience == q.audience)
            && (q.sizeSystem == nil || Self.same(c.sizeSystem, q.sizeSystem))
            && (q.productLine == nil || Self.same(c.productLine, q.productLine))
        }
        .sorted { a, b in
            if a.source.isDemoData != b.source.isDemoData { return !a.source.isDemoData }
            let aSpecific = !(a.productLine ?? "").isEmpty
            let bSpecific = !(b.productLine ?? "").isEmpty
            if aSpecific != bSpecific { return aSpecific }
            return a.displayTitle < b.displayTitle
        }
    }

    /// Picks the most specific chart for a product line, falling back to the brand-wide chart
    /// (one with no product line) when no product-specific chart exists.
    public func bestChart(brand: String, category: ClothingCategory, region: SizeRegion?, audience: SizeAudience?,
                          sizeSystem: String?, productLine: String?) -> SizeChart? {
        let base = SizeChartQuery(brand: brand, category: category, region: region, audience: audience, sizeSystem: sizeSystem)
        let candidates = charts(matching: base)
        if let p = productLine, !p.isEmpty, let specific = candidates.first(where: { Self.same($0.productLine, p) }) {
            return specific
        }
        return candidates.first(where: { ($0.productLine ?? "").isEmpty }) ?? candidates.first
    }

    public var brands: [String] {
        Array(Set(charts.map(\.brand))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func categories(brand: String) -> [ClothingCategory] {
        let cats = Set(charts.filter { Self.same($0.brand, brand) }.map(\.category))
        return ClothingCategory.allCases.filter { cats.contains($0) }
    }

    public func regions(brand: String, category: ClothingCategory) -> [SizeRegion] {
        let r = Set(charts(matching: .init(brand: brand, category: category)).map(\.region))
        return SizeRegion.allCases.filter { r.contains($0) }
    }

    public func audiences(brand: String, category: ClothingCategory, region: SizeRegion?) -> [SizeAudience] {
        let a = Set(charts(matching: .init(brand: brand, category: category, region: region)).map(\.audience))
        return SizeAudience.allCases.filter { a.contains($0) }
    }

    public func sizeSystems(brand: String, category: ClothingCategory, region: SizeRegion?, audience: SizeAudience?) -> [String] {
        Array(Set(charts(matching: .init(brand: brand, category: category, region: region, audience: audience)).map(\.sizeSystem))).sorted()
    }

    public func productLines(brand: String, category: ClothingCategory, region: SizeRegion?, audience: SizeAudience?, sizeSystem: String?) -> [String] {
        let lines = charts(matching: .init(brand: brand, category: category, region: region, audience: audience, sizeSystem: sizeSystem))
            .compactMap(\.productLine).filter { !$0.isEmpty }
        return Array(Set(lines)).sorted()
    }
}

/// File format for importing/exporting charts. Values in the file are in `unit`;
/// they are converted to centimetres on import.
public struct SizeChartFile: Codable, Sendable {
    public var formatVersion: Int
    public var unit: LengthUnit
    public var charts: [SizeChart]

    public static let currentVersion = 1

    public init(unit: LengthUnit = .centimetres, charts: [SizeChart]) {
        self.formatVersion = Self.currentVersion
        self.unit = unit
        self.charts = charts
    }

    public enum CodecError: Error, LocalizedError, Equatable {
        case unsupportedVersion(Int)
        case unreadable(String)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v): return "This chart file uses format version \(v), which this app does not support."
            case .unreadable(let reason): return "The chart file could not be read: \(reason)"
            }
        }
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = ISO8601DateFormatter().date(from: s) { return date }
            let day = DateFormatter()
            day.locale = Locale(identifier: "en_US_POSIX")
            day.timeZone = TimeZone(secondsFromGMT: 0)
            day.dateFormat = "yyyy-MM-dd"
            if let date = day.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected an ISO 8601 date, got \(s)")
        }
        return d
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    /// Decodes a chart file and returns charts with ranges in centimetres.
    public static func decodeCharts(from data: Data) throws -> [SizeChart] {
        let file: SizeChartFile
        do {
            file = try makeDecoder().decode(SizeChartFile.self, from: data)
        } catch let error as DecodingError {
            throw CodecError.unreadable(String(describing: error))
        }
        guard file.formatVersion == currentVersion else { throw CodecError.unsupportedVersion(file.formatVersion) }
        guard file.unit != .centimetres else { return file.charts }
        return file.charts.map { chart in
            var c = chart
            c.sizes = chart.sizes.map { size in
                var s = size
                s.measurements = size.measurements.mapValues {
                    MeasurementRange(minCM: file.unit.toCentimetres($0.minCM), maxCM: file.unit.toCentimetres($0.maxCM))
                }
                return s
            }
            return c
        }
    }

    public static func encode(_ charts: [SizeChart]) throws -> Data {
        try makeEncoder().encode(SizeChartFile(unit: .centimetres, charts: charts))
    }
}

public enum DemoSizeCharts {
    /// Loads the bundled, clearly-labelled demo charts. All brands in this file are fictional.
    public static func load() throws -> [SizeChart] {
        guard let url = Bundle.module.url(forResource: "DemoSizeCharts", withExtension: "json") else {
            throw SizeChartFile.CodecError.unreadable("DemoSizeCharts.json is missing from the bundle")
        }
        let charts = try SizeChartFile.decodeCharts(from: Data(contentsOf: url))
        // Defensive: anything in the demo file is demo data, whatever the file says.
        return charts.map { var c = $0; c.source.isDemoData = true; return c }
    }
}
