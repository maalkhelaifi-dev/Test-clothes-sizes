import XCTest
@testable import MeasureMeCore

final class UnitConversionTests: XCTestCase {
    func testInchesToCentimetres() {
        XCTAssertEqual(LengthUnit.inches.toCentimetres(1), 2.54, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.inches.toCentimetres(32), 81.28, accuracy: 1e-9)
    }

    func testCentimetresToInches() {
        XCTAssertEqual(LengthUnit.inches.fromCentimetres(100), 39.370078, accuracy: 1e-6)
        XCTAssertEqual(LengthUnit.centimetres.fromCentimetres(100), 100)
    }

    func testRoundTrip() {
        for v in stride(from: 10.0, through: 200.0, by: 7.3) {
            let back = LengthUnit.convert(LengthUnit.convert(v, from: .centimetres, to: .inches), from: .inches, to: .centimetres)
            XCTAssertEqual(back, v, accuracy: 1e-9)
        }
    }

    func testFormatting() {
        XCTAssertEqual(LengthUnit.centimetres.format(centimetres: 92.26), "92.5 cm")
        XCTAssertEqual(LengthUnit.centimetres.format(centimetres: 92.0), "92 cm")
        XCTAssertEqual(LengthUnit.inches.format(centimetres: 81.28), "32 in")
        XCTAssertEqual(LengthUnit.inches.format(centimetres: 2.54 * 32.25), "32.25 in")
        XCTAssertEqual(LengthUnit.inches.format(centimetres: 2.54 * 32.5), "32.5 in")
        XCTAssertEqual(LengthUnit.centimetres.formatUncertainty(centimetres: 3), "±3 cm")
    }

    func testParsing() {
        XCTAssertEqual(LengthUnit.centimetres.parseToCentimetres("92,5")!, 92.5, accuracy: 1e-9)
        XCTAssertEqual(LengthUnit.inches.parseToCentimetres(" 32 in ")!, 81.28, accuracy: 1e-9)
        XCTAssertNil(LengthUnit.centimetres.parseToCentimetres("abc"))
        XCTAssertNil(LengthUnit.centimetres.parseToCentimetres("-4"))
        XCTAssertNil(LengthUnit.centimetres.parseToCentimetres(""))
    }

    func testFeetInches() {
        let fi = FeetInches(centimetres: 175.26) // 5'9"
        XCTAssertEqual(fi.feet, 5)
        XCTAssertEqual(fi.inches, 9)
        XCTAssertEqual(FeetInches(feet: 6, inches: 0).centimetres, 182.88, accuracy: 1e-9)
        // Rounding to 12 inches rolls over to the next foot.
        let rolled = FeetInches(centimetres: 182.7)
        XCTAssertEqual(rolled.feet, 6)
        XCTAssertEqual(rolled.inches, 0)
    }
}
