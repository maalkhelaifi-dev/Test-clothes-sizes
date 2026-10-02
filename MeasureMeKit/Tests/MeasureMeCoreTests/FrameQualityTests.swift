import XCTest
@testable import MeasureMeCore

final class FrameQualityTests: XCTestCase {
    let p = SyntheticPerson()

    func input(_ joints: [BodyJoint: DetectedJoint], view: CaptureView = .front, luma: Double = 0.5,
               pitch: Double = 0, roll: Double = 0, people: Int = 1) -> FrameQualityInput {
        FrameQualityInput(expectedView: view, joints: joints, personCount: people, imageAspect: 1080.0 / 1920.0,
                          meanLuma: luma, devicePitchDegrees: pitch, deviceRollDegrees: roll, rotationRate: 0)
    }

    func testGoodFrontFramePasses() {
        let report = FrameQualityEvaluator.evaluate(input(p.frontJoints))
        XCTAssertTrue(report.allPassed, "\(report.checks.filter { !$0.passed })")
        XCTAssertEqual(report.score, 1, accuracy: 1e-9)
        XCTAssertNil(report.primaryInstruction)
    }

    func testNoPerson() {
        let report = FrameQualityEvaluator.evaluate(input([:], people: 0))
        XCTAssertEqual(report.primaryInstruction, "Step into the frame.")
    }

    func testMultiplePeople() {
        let report = FrameQualityEvaluator.evaluate(input(p.frontJoints, people: 2))
        XCTAssertFalse(report.checks.first { $0.kind == .person }!.passed)
    }

    func testDarkAndTilted() {
        let report = FrameQualityEvaluator.evaluate(input(p.frontJoints, luma: 0.1, pitch: 20))
        XCTAssertFalse(report.checks.first { $0.kind == .lighting }!.passed)
        XCTAssertFalse(report.checks.first { $0.kind == .phoneAngle }!.passed)
        XCTAssertLessThan(report.score, 1)
    }

    func testFeetCutOff() {
        var j = p.frontJoints
        j[.leftAnkle] = DetectedJoint(x: 0.4, y: 0.99, confidence: 0.9)
        j[.rightAnkle] = DetectedJoint(x: 0.6, y: 0.99, confidence: 0.9)
        let report = FrameQualityEvaluator.evaluate(input(j))
        XCTAssertFalse(report.checks.first { $0.kind == .fullBody }!.passed)
    }

    func testArmsAgainstBodyFailsPose() {
        var j = p.frontJoints
        j[.leftWrist] = j[.leftShoulder].map { DetectedJoint(x: $0.location.x, y: 0.8, confidence: 0.9) }
        j[.rightWrist] = j[.rightShoulder].map { DetectedJoint(x: $0.location.x, y: 0.8, confidence: 0.9) }
        let pose = FrameQualityEvaluator.evaluate(input(j)).checks.first { $0.kind == .pose }!
        XCTAssertFalse(pose.passed)
        XCTAssertTrue(pose.message.contains("arms"))
    }

    func testSideViewRequiresTurning() {
        // Front-facing joints when a side view is expected.
        let pose = FrameQualityEvaluator.evaluate(input(p.frontJoints, view: .side)).checks.first { $0.kind == .pose }!
        XCTAssertFalse(pose.passed)
        let sideOK = FrameQualityEvaluator.evaluate(input(p.side.joints, view: .side)).checks.first { $0.kind == .pose }!
        XCTAssertTrue(sideOK.passed)
    }

    func testMovementDetected() {
        var moved = p.frontJoints
        for (k, v) in moved { moved[k] = DetectedJoint(x: v.location.x + 0.08, y: v.location.y, confidence: v.confidence) }
        var i = input(moved)
        i.previousJoints = p.frontJoints
        XCTAssertFalse(FrameQualityEvaluator.evaluate(i).checks.first { $0.kind == .steady }!.passed)
    }

    func testFrameSelector() {
        XCTAssertEqual(FrameSelector.bestIndices(scores: [0.5, 0.9, 0.95, 0.85, 0.99], count: 3), [1, 2, 4])
        XCTAssertEqual(FrameSelector.bestIndices(scores: [0.5, 0.6], count: 3), [])
    }
}
