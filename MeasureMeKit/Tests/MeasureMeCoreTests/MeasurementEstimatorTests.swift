import XCTest
@testable import MeasureMeCore

final class MeasurementEstimatorTests: XCTestCase {

    func testEllipsePerimeter() {
        // Circle of diameter 10 → 10π.
        XCTAssertEqual(MeasurementEstimator.ellipsePerimeter(width: 10, depth: 10), 10 * .pi, accuracy: 1e-9)
        // Ramanujan II for a=16, b=12 (exact ≈ 88.4140).
        XCTAssertEqual(MeasurementEstimator.ellipsePerimeter(width: 32, depth: 24), 88.4140, accuracy: 0.01)
        XCTAssertEqual(MeasurementEstimator.ellipsePerimeter(width: 0, depth: 0), 0)
    }

    func testMaskHelpers() {
        let p = SyntheticPerson()
        let m = p.front.mask!
        let ext = try! XCTUnwrap(m.verticalExtent())
        XCTAssertEqual(ext.top, p.topRow)
        XCTAssertEqual(ext.bottom, p.bottomRow)
        // Leg gap appears at the crotch.
        let crotch = try! XCTUnwrap(m.crotchRow(centerX: m.width / 2, fromRow: p.row(0.53), toRow: p.row(0.28)))
        XCTAssertEqual(crotch, p.row(p.crotchFraction), accuracy: 2)
    }

    func testFrontAndSideEstimatesMatchSyntheticBody() throws {
        let p = SyntheticPerson()
        let result = MeasurementEstimator.estimate(heightCM: p.heightCM, fronts: [p.front], sides: [p.side])
        func value(_ k: MeasurementKind) throws -> Double { try XCTUnwrap(result.estimates[k]?.valueCM, "\(k) missing: \(result.estimates[k]?.unavailableReason ?? "")") }

        XCTAssertEqual(try value(.chest), MeasurementEstimator.ellipsePerimeter(width: 32, depth: 24), accuracy: 2.0)
        XCTAssertEqual(try value(.waist), MeasurementEstimator.ellipsePerimeter(width: 28, depth: 22), accuracy: 2.0)
        XCTAssertEqual(try value(.hips), MeasurementEstimator.ellipsePerimeter(width: 36, depth: 26), accuracy: 2.0)
        XCTAssertEqual(try value(.inseam), 0.47 * 170, accuracy: 2.0)
        XCTAssertEqual(try value(.shoulderWidth), 30 * 1.18, accuracy: 1.0)
        let upper = hypot(9.0, 0.19 * 170), lower = 0.16 * 170
        XCTAssertEqual(try value(.armLength), upper + lower, accuracy: 1.5)
        XCTAssertEqual(try value(.sleeveLength), 30 * 1.18 / 2 + upper + lower, accuracy: 2.0)
        XCTAssertEqual(result.estimates[.chest]?.confidence, .medium)
        XCTAssertNotNil(result.estimates[.thigh]?.valueCM)
        XCTAssertEqual(result.estimates[.thigh]?.confidence, .low)
        XCTAssertTrue(result.warnings.isEmpty, "unexpected warnings: \(result.warnings)")
    }

    func testAnisotropicMaskResolution() throws {
        var p = SyntheticPerson()
        p.maskWidth = 200   // mask aspect differs from image aspect
        let result = MeasurementEstimator.estimate(heightCM: p.heightCM, fronts: [p.front], sides: [p.side])
        let chest = try XCTUnwrap(result.estimates[.chest]?.valueCM)
        XCTAssertEqual(chest, MeasurementEstimator.ellipsePerimeter(width: 32, depth: 24), accuracy: 2.5)
    }

    func testGirthsUnavailableWithoutSideView() {
        let p = SyntheticPerson()
        let result = MeasurementEstimator.estimate(heightCM: p.heightCM, fronts: [p.front])
        for k in [MeasurementKind.chest, .waist, .hips] {
            XCTAssertNil(result.estimates[k]?.valueCM, "\(k) must not be invented from a single front view")
            XCTAssertTrue(result.estimates[k]!.unavailableReason!.contains("side"))
        }
        // Lengths are still available.
        XCTAssertNotNil(result.estimates[.inseam]?.valueCM)
    }

    func testManualOnlyMeasurementsAreNeverEstimated() {
        let p = SyntheticPerson()
        let result = MeasurementEstimator.estimate(heightCM: p.heightCM, fronts: [p.front], sides: [p.side])
        for k in MeasurementKind.allCases where k.cameraSupport == .manualOnly {
            XCTAssertNil(result.estimates[k]?.valueCM, "\(k)")
        }
        XCTAssertNil(result.estimates[.height], "height is user-provided")
    }

    func testArmsTouchingBodyLowersConfidence() {
        var p = SyntheticPerson()
        p.armsTouching = true
        let result = MeasurementEstimator.estimate(heightCM: p.heightCM, fronts: [p.front], sides: [p.side])
        XCTAssertEqual(result.estimates[.hips]?.confidence, .low)
        XCTAssertTrue(result.warnings.contains { $0.contains("arms") })
    }

    func testNoFrontViewReportsEverythingUnavailable() {
        let result = MeasurementEstimator.estimate(heightCM: 170, fronts: [])
        XCTAssertEqual(result.framesUsed, 0)
        XCTAssertTrue(result.estimates.values.allSatisfy { !$0.isAvailable })
    }

    func testDepthScaleDisagreementWarns() {
        let p = SyntheticPerson()
        var front = p.front
        let trueScale = p.cmPerRow / (Double(p.imageHeight) / Double(p.maskHeight))
        front.depthCMPerImagePixel = trueScale * 1.2
        let result = MeasurementEstimator.estimate(heightCM: p.heightCM, fronts: [front], sides: [p.side])
        XCTAssertTrue(result.warnings.contains { $0.contains("LiDAR") })
        XCTAssertEqual(result.estimates[.armLength]?.confidence, .medium)
    }

    func testMultipleFramesUseMedianAndSpread() throws {
        let a = SyntheticPerson()
        var b = SyntheticPerson(); b.chestWidth = 36
        var c = SyntheticPerson(); c.chestWidth = 28
        let result = MeasurementEstimator.estimate(heightCM: 170, fronts: [a.front, b.front, c.front], sides: [a.side])
        let chest = try XCTUnwrap(result.estimates[.chest])
        XCTAssertEqual(chest.valueCM!, MeasurementEstimator.ellipsePerimeter(width: 32, depth: 24), accuracy: 2.0)
        XCTAssertGreaterThan(chest.uncertaintyCM, 4.0)
        XCTAssertEqual(result.framesUsed, 3)
    }

    func testCalibrationFactorsApply() throws {
        let p = SyntheticPerson()
        let cal = CalibrationProfile(name: "test", factors: [.waist: 1.1])
        let base = try XCTUnwrap(MeasurementEstimator.estimate(heightCM: 170, fronts: [p.front], sides: [p.side]).estimates[.waist]?.valueCM)
        let scaled = try XCTUnwrap(MeasurementEstimator.estimate(heightCM: 170, fronts: [p.front], sides: [p.side], calibration: cal).estimates[.waist]?.valueCM)
        XCTAssertEqual(scaled / base, 1.1, accuracy: 1e-6)
    }

    func testResultConvertsToMeasurementSet() {
        let p = SyntheticPerson()
        let set = MeasurementEstimator.estimate(heightCM: 170, fronts: [p.front], sides: [p.side]).measurementSet()
        XCTAssertEqual(set[.chest]?.source, .cameraEstimate)
        XCTAssertNil(set[.underbust])
    }
}
