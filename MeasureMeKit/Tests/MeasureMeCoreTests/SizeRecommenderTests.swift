import XCTest
@testable import MeasureMeCore

final class SizeRecommenderTests: XCTestCase {
    let demoSource = ChartSource(url: nil, lastVerified: nil, isDemoData: true)

    func topsChart() -> SizeChart {
        SizeChart(brand: "T", category: .tops, audience: .unisex, region: .international, sizeSystem: "Letter", measurementType: .body,
                  sizes: [
                    SizeEntry(label: "S", measurements: [.chest: .init(minCM: 88, maxCM: 93), .waist: .init(minCM: 74, maxCM: 79)]),
                    SizeEntry(label: "M", measurements: [.chest: .init(minCM: 94, maxCM: 99), .waist: .init(minCM: 80, maxCM: 85)]),
                    SizeEntry(label: "L", measurements: [.chest: .init(minCM: 100, maxCM: 106), .waist: .init(minCM: 86, maxCM: 92)]),
                  ], source: demoSource)
    }

    func set(_ pairs: [(MeasurementKind, Double)], confidence: ConfidenceLevel = .high, uncertainty: Double = 1) -> MeasurementSet {
        MeasurementSet(pairs.map { MeasurementValue(kind: $0.0, valueCM: $0.1, source: .manual, confidence: confidence, uncertaintyCM: uncertainty) })
    }

    func recommended(_ o: RecommendationOutcome, file: StaticString = #filePath, line: UInt = #line) -> SizeRecommendation? {
        if case .recommended(let r) = o { return r }
        XCTFail("Expected a recommendation, got \(o)", file: file, line: line)
        return nil
    }

    func testPicksSizeContainingMeasurements() {
        let r = recommended(SizeRecommender.recommend(chart: topsChart(), measurements: set([(.chest, 96.5), (.waist, 82)]), fit: .regular))
        XCTAssertEqual(r?.size, "M")
        XCTAssertNil(r?.alternativeSize)
        XCTAssertEqual(r?.drivingMeasurements, [.chest])
        XCTAssertEqual(r?.comparisons.first { $0.kind == .chest }?.status, .within)
        XCTAssertEqual(r?.confidence, .high)
        XCTAssertTrue(r!.isDemoChart)
    }

    func testFitPreferenceDecidesBetweenSizes() {
        // 93.6 cm sits in the gap between S (≤93) and M (≥94).
        let m = set([(.chest, 93.6)])
        XCTAssertEqual(recommended(SizeRecommender.recommend(chart: topsChart(), measurements: m, fit: .slim))?.size, "S")
        XCTAssertEqual(recommended(SizeRecommender.recommend(chart: topsChart(), measurements: m, fit: .relaxed))?.size, "M")
    }

    func testCloseCallOffersAlternative() {
        let r = recommended(SizeRecommender.recommend(chart: topsChart(), measurements: set([(.chest, 99)], uncertainty: 3), fit: .regular))
        XCTAssertEqual(r?.size, "M")
        XCTAssertEqual(r?.alternativeSize, "L")
        XCTAssertNotNil(r?.alternativeReason)
        XCTAssertEqual(r?.confidence, .medium)
    }

    func testInsufficientWhenChartLacksPrimaryMeasurement() {
        let chart = SizeChart(brand: "T", category: .tops, audience: .unisex, region: .uk, sizeSystem: "L", measurementType: .body,
                              sizes: [SizeEntry(label: "M", measurements: [.waist: .init(minCM: 80, maxCM: 85)])], source: demoSource)
        guard case .insufficientData(let reasons, _) = SizeRecommender.recommend(chart: chart, measurements: set([(.waist, 82)]), fit: .regular) else {
            return XCTFail("expected insufficient data")
        }
        XCTAssertFalse(reasons.isEmpty)
    }

    func testInsufficientWhenUserLacksPrimaryMeasurement() {
        guard case .insufficientData(_, let missing) = SizeRecommender.recommend(chart: topsChart(), measurements: set([(.waist, 82)]), fit: .regular) else {
            return XCTFail("expected insufficient data")
        }
        XCTAssertEqual(missing, [.chest])
    }

    func testConflictingMeasurementsAreReported() throws {
        let lib = SizeChartLibrary(charts: try DemoSizeCharts.load())
        let trousers = try XCTUnwrap(lib.charts(matching: .init(category: .trousers)).first)
        // Waist points to W30, hips to W34.
        let r = recommended(SizeRecommender.recommend(chart: trousers, measurements: set([(.waist, 76), (.hips, 100)]), fit: .regular))
        XCTAssertNotNil(r)
        XCTAssertFalse(r!.conflictingMeasurements.isEmpty)
        XCTAssertNotNil(r!.alternativeSize)
    }

    func testOutsideChartRange() {
        guard case .outsideChartRange(let nearest, _, let lines) = SizeRecommender.recommend(chart: topsChart(), measurements: set([(.chest, 130)]), fit: .regular) else {
            return XCTFail("expected outside range")
        }
        XCTAssertEqual(nearest, "L")
        XCTAssertTrue(lines.joined().contains("larger"))
    }

    func testLowConfidenceMeasurementLowersRecommendationConfidence() {
        let r = recommended(SizeRecommender.recommend(chart: topsChart(), measurements: set([(.chest, 96.5)], confidence: .low), fit: .regular))
        XCTAssertEqual(r?.confidence, .low)
        XCTAssertTrue(r!.explanation.joined().contains("Low-confidence"))
    }

    func testGarmentChartUsesEaseAndCapsConfidence() throws {
        let lib = SizeChartLibrary(charts: try DemoSizeCharts.load())
        let blazer = try XCTUnwrap(lib.charts(matching: .init(category: .jackets, productLine: "Signature Slim Blazer")).first)
        // Garment chest 106 (size 48) − 12 cm regular jacket ease = 94 body.
        let r = recommended(SizeRecommender.recommend(chart: blazer, measurements: set([(.chest, 94)]), fit: .regular))
        XCTAssertEqual(r?.size, "48")
        XCTAssertEqual(r?.chartType, .garment)
        XCTAssertEqual(r?.confidence, .medium)
        // Relaxed fit adds more ease, so the same body needs a bigger garment.
        let relaxed = recommended(SizeRecommender.recommend(chart: blazer, measurements: set([(.chest, 94)]), fit: .relaxed))
        XCTAssertEqual(relaxed?.size, "50")
    }

    func testPointRangesAreWidenedToMidpoints() throws {
        let lib = SizeChartLibrary(charts: try DemoSizeCharts.load())
        let blazer = try XCTUnwrap(lib.charts(matching: .init(category: .jackets, productLine: "Signature Slim Blazer")).first)
        let table = SizeRecommender.bodyRangeTable(chart: blazer, fit: .regular)
        // 48: garment 106, neighbours 102 and 110 → 104–108 garment → 92–96 body.
        XCTAssertEqual(table["48"]![.chest]!.minCM, 92, accuracy: 1e-9)
        XCTAssertEqual(table["48"]![.chest]!.maxCM, 96, accuracy: 1e-9)
    }

    func testAllDemoChartsProduceAnOutcome() throws {
        let m = set([(.chest, 96), (.waist, 82), (.hips, 98), (.neck, 39.5), (.sleeveLength, 84), (.shoulderWidth, 45), (.armLength, 62)])
        for chart in try DemoSizeCharts.load() {
            switch SizeRecommender.recommend(chart: chart, measurements: m, fit: .regular) {
            case .recommended(let r): XCTAssertFalse(r.size.isEmpty)
            case .outsideChartRange: break
            case .insufficientData(let reasons, _): XCTFail("\(chart.displayTitle): \(reasons)")
            }
        }
    }
}
