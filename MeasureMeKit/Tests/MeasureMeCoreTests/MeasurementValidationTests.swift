import XCTest
@testable import MeasureMeCore

final class MeasurementValidationTests: XCTestCase {
    func testPlausibleValuePasses() {
        XCTAssertTrue(MeasurementValidator.validate(.chest, cm: 96).isEmpty)
        XCTAssertTrue(MeasurementValidator.validate(.height, cm: 170).isEmpty)
    }

    func testRejectsNonPositiveAndNonFinite() {
        XCTAssertEqual(MeasurementValidator.validate(.waist, cm: 0).first?.code, "notPositive")
        XCTAssertEqual(MeasurementValidator.validate(.waist, cm: .nan).first?.code, "notPositive")
        XCTAssertEqual(MeasurementValidator.validate(.waist, cm: -3).first?.severity, .error)
    }

    func testOutOfRangeSuggestsUnitMistake() {
        // 36 cm chest is implausible but 36 inches is plausible → hint about inches.
        let issues = MeasurementValidator.validate(.chest, cm: 36)
        XCTAssertEqual(issues.first?.code, "outOfRange")
        XCTAssertTrue(issues.first!.message.contains("inches"))
    }

    func testCrossChecks() {
        let set = MeasurementSet([
            .manual(.height, cm: 170),
            .manual(.inseam, cm: 100),
            .manual(.outseam, cm: 98),
            .manual(.armLength, cm: 64),
            .manual(.sleeveLength, cm: 63),
        ])
        let codes = Set(MeasurementValidator.validate(set).map(\.code))
        XCTAssertTrue(codes.contains("inseamVsHeight"))
        XCTAssertTrue(codes.contains("inseamVsOutseam"))
        XCTAssertTrue(codes.contains("sleeveVsArm"))
        XCTAssertFalse(MeasurementValidator.hasErrors(MeasurementValidator.validate(set)))
    }

    func testConsistentSetHasNoIssues() {
        let set = MeasurementSet([
            .manual(.height, cm: 175), .manual(.chest, cm: 98), .manual(.waist, cm: 84),
            .manual(.hips, cm: 99), .manual(.inseam, cm: 80), .manual(.outseam, cm: 105),
            .manual(.armLength, cm: 61), .manual(.sleeveLength, cm: 84),
        ])
        XCTAssertTrue(MeasurementValidator.validate(set).isEmpty)
    }

    func testProfileRequiresAdultConfirmation() {
        let p = PersonProfile(displayName: "Me", heightCM: 170, adultConfirmed: false)
        XCTAssertThrowsError(try p.validate()) { error in
            XCTAssertEqual(error as? PersonProfile.ProfileError, .adultConfirmationRequired)
        }
        XCTAssertNoThrow(try PersonProfile(displayName: "Me", heightCM: 170, adultConfirmed: true).validate())
        XCTAssertThrowsError(try PersonProfile(displayName: "  ", heightCM: 170, adultConfirmed: true).validate())
        XCTAssertThrowsError(try PersonProfile(displayName: "Me", heightCM: 70, adultConfirmed: true).validate())
    }

    func testEditingCameraValueKeepsOriginal() {
        let cam = MeasurementValue(kind: .waist, valueCM: 84, source: .cameraEstimate, confidence: .medium, uncertaintyCM: 4)
        let edited = cam.edited(toCM: 81)
        XCTAssertEqual(edited.source, .cameraEdited)
        XCTAssertEqual(edited.originalCameraValueCM, 84)
        XCTAssertEqual(edited.valueCM, 81)
        XCTAssertEqual(edited.confidence, .high)
        // Editing again keeps the first camera value.
        XCTAssertEqual(edited.edited(toCM: 80).originalCameraValueCM, 84)
    }

    func testMeasurementSetCodableRoundTrip() throws {
        let set = MeasurementSet([.manual(.chest, cm: 98), .manual(.waist, cm: 80)])
        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(try JSONDecoder().decode(MeasurementSet.self, from: data), set)
    }

    func testLatestMeasurementsMergeHistory() {
        let old = MeasurementSession(date: Date(timeIntervalSince1970: 0), method: .manual,
                                     measurements: MeasurementSet([.manual(.chest, cm: 90), .manual(.waist, cm: 80)]))
        let new = MeasurementSession(date: Date(timeIntervalSince1970: 100), method: .manual,
                                     measurements: MeasurementSet([.manual(.chest, cm: 95)]))
        let p = PersonProfile(displayName: "A", heightCM: 172, adultConfirmed: true, sessions: [new, old])
        XCTAssertEqual(p.latestMeasurements[.chest]?.valueCM, 95)
        XCTAssertEqual(p.latestMeasurements[.waist]?.valueCM, 80)
        XCTAssertEqual(p.latestMeasurements[.height]?.valueCM, 172)
        XCTAssertEqual(p.history.first?.id, new.id)
    }

    func testSessionMethodInference() {
        XCTAssertEqual(MeasurementSession.inferMethod(for: MeasurementSet([.manual(.chest, cm: 90)])), .manual)
        let cam = MeasurementValue(kind: .chest, valueCM: 90, source: .cameraEstimate, confidence: .medium, uncertaintyCM: 4)
        XCTAssertEqual(MeasurementSession.inferMethod(for: MeasurementSet([cam])), .camera)
        XCTAssertEqual(MeasurementSession.inferMethod(for: MeasurementSet([cam, .manual(.waist, cm: 80)])), .mixed)
    }
}
