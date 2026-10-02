import Foundation
@testable import MeasureMeCore

/// Draws simple synthetic silhouettes with known dimensions for estimator tests.
/// Body proportions are expressed as fractions of stature above the floor.
struct SyntheticPerson {
    var heightCM = 170.0
    var maskWidth = 270
    var maskHeight = 480
    var imageWidth = 1080
    var imageHeight = 1920
    var topRow = 40
    var bodyRows = 400

    var chestWidth = 32.0, chestDepth = 24.0
    var waistWidth = 28.0, waistDepth = 22.0
    var hipWidth = 36.0, hipDepth = 26.0
    var crotchFraction = 0.47
    var armsTouching = false

    var cmPerRow: Double { heightCM / Double(bodyRows) }
    /// Columns per cm (square image pixels; mask may be anisotropic).
    var colsPerCM: Double {
        let cmPerImagePx = cmPerRow / (Double(imageHeight) / Double(maskHeight))
        return 1 / (cmPerImagePx * Double(imageWidth) / Double(maskWidth))
    }
    var bottomRow: Int { topRow + bodyRows - 1 }
    func row(_ f: Double) -> Int { Int((Double(bottomRow) - f * Double(bodyRows)).rounded()) }
    var centerCol: Double { Double(maskWidth) / 2 }
    func col(_ cm: Double) -> Int { Int((centerCol + cm * colsPerCM).rounded()) }

    var armOffset: Double { armsTouching ? hipWidth / 2 + 3.5 : 24 }

    /// Horizontal segments (cm from centre) of the front silhouette at a given stature fraction.
    func frontSegments(_ f: Double) -> [(Double, Double)] {
        var segs: [(Double, Double)] = []
        switch f {
        case 0.87...1.0: segs.append((-7.5, 7.5))
        case 0.83..<0.87: segs.append((-6, 6))
        case 0.765..<0.83: segs.append((-18, 18))
        case 0.66..<0.765: segs.append((-chestWidth / 2, chestWidth / 2))
        case 0.58..<0.66: segs.append((-waistWidth / 2, waistWidth / 2))
        case crotchFraction..<0.58: segs.append((-hipWidth / 2, hipWidth / 2))
        case 0.0..<crotchFraction:
            segs.append((-16, -2)); segs.append((2, 16))
        default: break
        }
        if f >= 0.45 && f < 0.80 {
            segs.append((-armOffset - 4, -armOffset + 4)); segs.append((armOffset - 4, armOffset + 4))
        }
        return segs
    }

    /// Front-to-back depth (cm) of the side silhouette.
    func sideDepth(_ f: Double) -> Double? {
        switch f {
        case 0.87...1.0: return 20
        case 0.83..<0.87: return 12
        case 0.765..<0.83: return 22
        case 0.66..<0.765: return chestDepth
        case 0.58..<0.66: return waistDepth
        case crotchFraction..<0.58: return hipDepth
        case 0.0..<crotchFraction: return 16
        default: return nil
        }
    }

    func mask(_ segmentsAt: (Double) -> [(Double, Double)]) -> SilhouetteMask {
        var data = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        for y in topRow...bottomRow {
            let f = Double(bottomRow - y) / Double(bodyRows)
            for (a, b) in segmentsAt(f) {
                for x in max(0, col(a))..<min(maskWidth, col(b)) { data[y * maskWidth + x] = 255 }
            }
        }
        return SilhouetteMask(width: maskWidth, height: maskHeight, data: data)
    }

    func joint(_ xCM: Double, _ f: Double, _ c: Double = 0.9) -> DetectedJoint {
        DetectedJoint(x: Double(col(xCM)) / Double(maskWidth), y: Double(row(f)) / Double(maskHeight), confidence: c)
    }

    var frontJoints: [BodyJoint: DetectedJoint] {
        [
            .nose: joint(0, 0.93), .leftEye: joint(-3, 0.94), .rightEye: joint(3, 0.94),
            .neck: joint(0, 0.82),
            .leftShoulder: joint(-15, 0.82), .rightShoulder: joint(15, 0.82),
            .leftElbow: joint(-armOffset, 0.63), .rightElbow: joint(armOffset, 0.63),
            .leftWrist: joint(-armOffset, 0.47), .rightWrist: joint(armOffset, 0.47),
            .leftHip: joint(-9, 0.53), .rightHip: joint(9, 0.53), .root: joint(0, 0.53),
            .leftKnee: joint(-9, 0.28), .rightKnee: joint(9, 0.28),
            .leftAnkle: joint(-9, 0.04), .rightAnkle: joint(9, 0.04),
        ]
    }

    var front: ViewObservation {
        ViewObservation(view: .front, imageWidth: imageWidth, imageHeight: imageHeight, joints: frontJoints, mask: mask(frontSegments))
    }

    var side: ViewObservation {
        let m = mask { f in sideDepth(f).map { [(-$0 / 2, $0 / 2)] } ?? [] }
        let joints: [BodyJoint: DetectedJoint] = [
            .nose: joint(5, 0.93), .neck: joint(0, 0.82), .leftShoulder: joint(0, 0.82), .rightShoulder: joint(1, 0.82),
            .leftHip: joint(0, 0.53), .leftAnkle: joint(0, 0.04), .rightAnkle: joint(1, 0.04),
        ]
        return ViewObservation(view: .side, imageWidth: imageWidth, imageHeight: imageHeight, joints: joints, mask: m)
    }
}
