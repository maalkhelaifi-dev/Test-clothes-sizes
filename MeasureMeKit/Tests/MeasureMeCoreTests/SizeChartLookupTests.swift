import XCTest
@testable import MeasureMeCore

final class SizeChartLookupTests: XCTestCase {
    func testDemoChartsLoadAndAreFlaggedAsDemo() throws {
        let charts = try DemoSizeCharts.load()
        XCTAssertFalse(charts.isEmpty)
        for c in charts {
            XCTAssertTrue(c.source.isDemoData, "\(c.displayTitle) must be demo data")
            XCTAssertTrue(c.brand.contains("(Demo)"), "Demo brand names must say Demo")
            XCTAssertTrue(c.trustLabel.hasPrefix("DEMO DATA"))
            XCTAssertNoThrow(try SizeChartValidator.validate(c, isUserChart: false))
        }
    }

    func testQueryFilters() throws {
        let lib = SizeChartLibrary(charts: try DemoSizeCharts.load())
        let tops = lib.charts(matching: .init(category: .tops))
        XCTAssertTrue(tops.allSatisfy { $0.category == .tops })
        XCTAssertFalse(tops.isEmpty)
        XCTAssertTrue(lib.charts(matching: .init(brand: "aurora basics (demo)", category: .trousers, region: .eu)).count == 1)
        XCTAssertTrue(lib.charts(matching: .init(includeDemoData: false)).isEmpty)
        XCTAssertTrue(lib.brands.contains("Tidewater Tailoring (Demo)"))
        XCTAssertEqual(lib.categories(brand: "Tidewater Tailoring (Demo)"), [.jackets, .suits, .dresses])
    }

    func testBestChartPrefersProductLineAndFallsBack() throws {
        let lib = SizeChartLibrary(charts: try DemoSizeCharts.load())
        let brand = "Tidewater Tailoring (Demo)"
        let specific = lib.bestChart(brand: brand, category: .jackets, region: .eu, audience: .unisex, sizeSystem: nil, productLine: "Signature Slim Blazer")
        XCTAssertEqual(specific?.productLine, "Signature Slim Blazer")
        XCTAssertEqual(specific?.measurementType, .garment)
        let general = lib.bestChart(brand: brand, category: .jackets, region: .eu, audience: .unisex, sizeSystem: nil, productLine: "Unknown Line")
        XCTAssertNil(general?.productLine)
        XCTAssertEqual(general?.measurementType, .body)
        XCTAssertEqual(lib.productLines(brand: brand, category: .jackets, region: nil, audience: nil, sizeSystem: nil), ["Signature Slim Blazer"])
    }

    func testUserChartRequiresSourceAndVerificationDate() {
        var chart = SizeChart(brand: "Real Brand", category: .tops, audience: .unisex, region: .uk, sizeSystem: "Letter",
                              measurementType: .body,
                              sizes: [SizeEntry(label: "M", measurements: [.chest: .init(minCM: 96, maxCM: 101)])],
                              source: ChartSource(url: nil, lastVerified: nil, isDemoData: false))
        XCTAssertThrowsError(try SizeChartValidator.validate(chart)) { XCTAssertEqual($0 as? SizeChartValidationError, .missingSourceURL) }
        chart.source.url = URL(string: "https://example.com/size-guide")
        XCTAssertThrowsError(try SizeChartValidator.validate(chart)) { XCTAssertEqual($0 as? SizeChartValidationError, .missingVerificationDate) }
        chart.source.lastVerified = Date().addingTimeInterval(10 * 86400)
        XCTAssertThrowsError(try SizeChartValidator.validate(chart)) { XCTAssertEqual($0 as? SizeChartValidationError, .verificationDateInFuture) }
        chart.source.lastVerified = Date()
        XCTAssertNoThrow(try SizeChartValidator.validate(chart))
        chart.source.isDemoData = true
        XCTAssertThrowsError(try SizeChartValidator.validate(chart)) { XCTAssertEqual($0 as? SizeChartValidationError, .demoFlagOnUserChart) }
    }

    func testValidationCatchesBadSizes() {
        let src = ChartSource(url: URL(string: "https://example.com"), lastVerified: Date(), isDemoData: false)
        let dup = SizeChart(brand: "B", category: .tops, audience: .unisex, region: .uk, sizeSystem: "L", measurementType: .body,
                            sizes: [SizeEntry(label: "M", measurements: [.chest: .init(pointCM: 90)]),
                                    SizeEntry(label: "m", measurements: [.chest: .init(pointCM: 95)])], source: src)
        XCTAssertThrowsError(try SizeChartValidator.validate(dup)) { XCTAssertEqual($0 as? SizeChartValidationError, .duplicateLabel("m")) }
        let empty = SizeChart(brand: "B", category: .tops, audience: .unisex, region: .uk, sizeSystem: "L", measurementType: .body,
                              sizes: [SizeEntry(label: "M", measurements: [:])], source: src)
        XCTAssertThrowsError(try SizeChartValidator.validate(empty))
        let noBrand = SizeChart(brand: " ", category: .tops, audience: .unisex, region: .uk, sizeSystem: "L", measurementType: .body, sizes: [], source: src)
        XCTAssertThrowsError(try SizeChartValidator.validate(noBrand)) { XCTAssertEqual($0 as? SizeChartValidationError, .missingBrand) }
    }

    func testWarningsForOverlapAndOrder() {
        let src = ChartSource(url: nil, lastVerified: nil, isDemoData: true)
        let c = SizeChart(brand: "B", category: .tops, audience: .unisex, region: .uk, sizeSystem: "L", measurementType: .body,
                          sizes: [SizeEntry(label: "S", measurements: [.chest: .init(minCM: 88, maxCM: 95)]),
                                  SizeEntry(label: "M", measurements: [.chest: .init(minCM: 93, maxCM: 99)]),
                                  SizeEntry(label: "L", measurements: [.chest: .init(minCM: 90, maxCM: 92)])], source: src)
        let w = SizeChartValidator.warnings(for: c)
        XCTAssertTrue(w.contains(.overlappingRanges(.chest, "S", "M")))
        XCTAssertTrue(w.contains(.sizesNotIncreasing(.chest)))
    }

    func testImportInInchesConvertsToCentimetres() throws {
        let json = """
        {"formatVersion":1,"unit":"in","charts":[{"id":"00000000-0000-0000-0000-000000000001","brand":"Imported","category":"shirts",
        "audience":"mens","region":"us","sizeSystem":"Neck","measurementType":"body",
        "sizes":[{"label":"15","measurements":{"neck":{"minCM":15,"maxCM":15.25},"chest":{"minCM":38,"maxCM":40}}}],
        "source":{"isDemoData":false,"url":"https://example.com/chart","lastVerified":"2026-09-01"}}]}
        """
        let charts = try SizeChartFile.decodeCharts(from: Data(json.utf8))
        let size = try XCTUnwrap(charts.first?.sizes.first)
        XCTAssertEqual(size.measurements[.neck]!.minCM, 38.1, accuracy: 1e-9)
        XCTAssertEqual(size.measurements[.chest]!.maxCM, 101.6, accuracy: 1e-9)
        XCTAssertNotNil(charts.first?.source.lastVerified)
        XCTAssertNoThrow(try SizeChartValidator.validate(charts[0]))
    }

    func testExportImportRoundTrip() throws {
        let charts = try DemoSizeCharts.load()
        let back = try SizeChartFile.decodeCharts(from: try SizeChartFile.encode(charts))
        XCTAssertEqual(back.count, charts.count)
        XCTAssertEqual(back.first?.sizes, charts.first?.sizes)
    }

    func testRejectsUnsupportedVersion() {
        let json = #"{"formatVersion":99,"unit":"cm","charts":[]}"#
        XCTAssertThrowsError(try SizeChartFile.decodeCharts(from: Data(json.utf8))) {
            XCTAssertEqual($0 as? SizeChartFile.CodecError, .unsupportedVersion(99))
        }
    }

    func testGarmentFlatWidthIsDoubledAndEaseSubtracted() throws {
        let lib = SizeChartLibrary(charts: try DemoSizeCharts.load())
        let coat = try XCTUnwrap(lib.charts(matching: .init(category: .outerwear)).first)
        XCTAssertEqual(coat.garmentConvention, .flatHalfWidth)
        let m = try XCTUnwrap(coat.sizes.first { $0.label == "M" })
        let r = try XCTUnwrap(coat.bodyEquivalentRange(for: .chest, in: m, fit: .regular))
        // 59 cm flat → 118 cm garment − 16 cm regular outerwear ease = 102 cm body.
        XCTAssertEqual(r.minCM, 102, accuracy: 1e-9)
    }
}
