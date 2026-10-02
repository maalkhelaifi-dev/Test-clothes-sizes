import Vision
import MeasureMeCore

/// Converts Vision observations into the framework-free types used by MeasureMeCore.
///
/// https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest
/// https://developer.apple.com/documentation/vision/vnhumanbodyposeobservation
enum VisionConversions {
    static let jointMap: [VNHumanBodyPoseObservation.JointName: BodyJoint] = [
        .nose: .nose, .leftEye: .leftEye, .rightEye: .rightEye, .leftEar: .leftEar, .rightEar: .rightEar,
        .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .root: .root,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    /// Joints in normalised top-left coordinates (Vision uses a bottom-left origin).
    /// Assumes the request ran with `.up` orientation on an already-portrait image.
    static func joints(from observation: VNHumanBodyPoseObservation) -> [BodyJoint: DetectedJoint] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var result: [BodyJoint: DetectedJoint] = [:]
        for (name, point) in points {
            guard let joint = jointMap[name], point.confidence > 0 else { continue }
            result[joint] = DetectedJoint(x: Double(point.location.x), y: 1 - Double(point.location.y),
                                          confidence: Double(point.confidence))
        }
        return result
    }

    /// Number of observations that look like a real person (enough confident joints).
    static func personCount(_ observations: [VNHumanBodyPoseObservation]) -> Int {
        observations.filter { obs in
            ((try? obs.recognizedPoints(.all))?.values.filter { $0.confidence > 0.3 }.count ?? 0) >= 6
        }.count
    }

    /// The observation covering the largest area — the person standing in front of the camera.
    static func mostProminent(_ observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { area($0) < area($1) }
    }

    private static func area(_ obs: VNHumanBodyPoseObservation) -> Double {
        guard let pts = try? obs.recognizedPoints(.all).values.filter({ $0.confidence > 0.3 }), !pts.isEmpty else { return 0 }
        let xs = pts.map { Double($0.location.x) }, ys = pts.map { Double($0.location.y) }
        return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
    }
}
