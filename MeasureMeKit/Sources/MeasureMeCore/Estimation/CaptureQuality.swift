import Foundation

/// Inputs for evaluating one live camera frame.
public struct FrameQualityInput: Sendable {
    public var expectedView: CaptureView
    /// Joints in normalised top-left coordinates for the single most prominent person.
    public var joints: [BodyJoint: DetectedJoint]
    public var personCount: Int
    /// Image width / height (portrait ≈ 0.5625 for 9:16).
    public var imageAspect: Double
    /// Mean luma 0…1, when measured.
    public var meanLuma: Double?
    /// Forward/back tilt of the phone away from vertical, degrees (0 = upright).
    public var devicePitchDegrees: Double?
    /// Sideways tilt of the phone, degrees (0 = level).
    public var deviceRollDegrees: Double?
    /// Device rotation rate magnitude, rad/s.
    public var rotationRate: Double?
    /// Joints from the previous analysed frame, to detect movement.
    public var previousJoints: [BodyJoint: DetectedJoint]?

    public init(expectedView: CaptureView, joints: [BodyJoint: DetectedJoint], personCount: Int, imageAspect: Double,
                meanLuma: Double? = nil, devicePitchDegrees: Double? = nil, deviceRollDegrees: Double? = nil,
                rotationRate: Double? = nil, previousJoints: [BodyJoint: DetectedJoint]? = nil) {
        self.expectedView = expectedView
        self.joints = joints
        self.personCount = personCount
        self.imageAspect = imageAspect
        self.meanLuma = meanLuma
        self.devicePitchDegrees = devicePitchDegrees
        self.deviceRollDegrees = deviceRollDegrees
        self.rotationRate = rotationRate
        self.previousJoints = previousJoints
    }
}

public struct QualityCheck: Equatable, Identifiable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case person, fullBody, distance, centered, lighting, phoneAngle, steady, pose
        public var displayName: String {
            switch self {
            case .person: return "One person"
            case .fullBody: return "Whole body visible"
            case .distance: return "Distance"
            case .centered: return "Centred"
            case .lighting: return "Lighting"
            case .phoneAngle: return "Phone upright"
            case .steady: return "Holding still"
            case .pose: return "Pose"
            }
        }
    }
    public var id: Kind { kind }
    public let kind: Kind
    public let passed: Bool
    /// Instruction shown/spoken when the check fails, or a confirmation when it passes.
    public let message: String
}

public struct FrameQualityReport: Equatable, Sendable {
    public let checks: [QualityCheck]
    /// Weighted fraction of checks passed, 0…1.
    public let score: Double

    public var allPassed: Bool { checks.allSatisfy(\.passed) }
    /// The most important failing instruction, for a single prominent prompt.
    public var primaryInstruction: String? { checks.first { !$0.passed }?.message }
}

/// Rule-based live checks for framing, lighting, phone angle, stability and pose.
/// Thresholds are starting points; tune them with device testing.
public enum FrameQualityEvaluator {

    public struct Thresholds: Sendable {
        public var minJointConfidence = 0.3
        public var minBodyFraction = 0.55
        public var maxBodyFraction = 0.88
        public var minLuma = 0.22
        public var maxLuma = 0.88
        public var maxPitch = 10.0
        public var maxRoll = 6.0
        public var maxRotationRate = 0.35
        public var maxJointMovement = 0.02
        public init() {}
    }

    public static func evaluate(_ input: FrameQualityInput, thresholds t: Thresholds = Thresholds()) -> FrameQualityReport {
        var checks: [QualityCheck] = []
        let j = input.joints.filter { $0.value.confidence >= t.minJointConfidence }
        func p(_ joint: BodyJoint) -> NormalizedPoint? { j[joint]?.location }
        let aspect = input.imageAspect

        // Order = priority of the instruction shown to the user.
        // 1. Person
        if input.personCount == 0 || j.isEmpty {
            checks.append(.init(kind: .person, passed: false, message: "Step into the frame."))
        } else if input.personCount > 1 {
            checks.append(.init(kind: .person, passed: false, message: "Only one person should be in view."))
        } else {
            checks.append(.init(kind: .person, passed: true, message: "One person detected."))
        }

        // 2. Lighting (independent of pose)
        if let luma = input.meanLuma {
            if luma < t.minLuma {
                checks.append(.init(kind: .lighting, passed: false, message: "It’s too dark. Turn on more lights or face a window."))
            } else if luma > t.maxLuma {
                checks.append(.init(kind: .lighting, passed: false, message: "It’s too bright. Avoid standing in front of a window or strong light."))
            } else {
                checks.append(.init(kind: .lighting, passed: true, message: "Lighting looks good."))
            }
        }

        // 3. Phone angle
        if let pitch = input.devicePitchDegrees, let roll = input.deviceRollDegrees {
            if abs(pitch) > t.maxPitch {
                checks.append(.init(kind: .phoneAngle, passed: false, message: pitch > 0 ? "Tilt the top of the phone back so it stands upright." : "Tilt the top of the phone forward so it stands upright."))
            } else if abs(roll) > t.maxRoll {
                checks.append(.init(kind: .phoneAngle, passed: false, message: "Straighten the phone so it isn’t leaning to one side."))
            } else {
                checks.append(.init(kind: .phoneAngle, passed: true, message: "Phone is upright."))
            }
        }

        let head = BodyJoint.head.compactMap { p($0) }
        let headTop = head.map(\.y).min() ?? p(.neck)?.y
        let ankles = [p(.leftAnkle), p(.rightAnkle)].compactMap { $0 }
        let feetY = ankles.map(\.y).max()

        // 4. Full body visible
        if let top = headTop, let feet = feetY {
            if top < 0.06 {
                checks.append(.init(kind: .fullBody, passed: false, message: "Your head is too close to the top. Step back or lower the phone slightly."))
            } else if feet > 0.95 {
                checks.append(.init(kind: .fullBody, passed: false, message: "Your feet are cut off. Step back so your whole body is visible."))
            } else {
                checks.append(.init(kind: .fullBody, passed: true, message: "Whole body visible."))
            }
        } else {
            checks.append(.init(kind: .fullBody, passed: false, message: headTop == nil ? "Make sure your head is in the frame." : "Make sure your feet are in the frame."))
        }

        // 5. Distance (body should fill most of the frame height, leaving margins)
        if let top = headTop, let feet = feetY {
            // Head joints sit below the top of the head; add ~6% of the visible span.
            let fraction = (feet - top) * 1.08
            if fraction < t.minBodyFraction {
                checks.append(.init(kind: .distance, passed: false, message: "Come a little closer to the camera."))
            } else if fraction > t.maxBodyFraction {
                checks.append(.init(kind: .distance, passed: false, message: "Step back a little."))
            } else {
                checks.append(.init(kind: .distance, passed: true, message: "Good distance."))
            }
        }

        // 6. Centred
        if let mid = midpoint(p(.leftHip), p(.rightHip)) ?? p(.root) ?? p(.neck) {
            if mid.x < 0.35 {
                checks.append(.init(kind: .centered, passed: false, message: "Move a little to your left so you’re in the centre."))
            } else if mid.x > 0.65 {
                checks.append(.init(kind: .centered, passed: false, message: "Move a little to your right so you’re in the centre."))
            } else {
                checks.append(.init(kind: .centered, passed: true, message: "You’re centred."))
            }
        }

        // 7. Pose for the expected view
        checks.append(poseCheck(view: input.expectedView, p: p, aspect: aspect, headTop: headTop, feetY: feetY))

        // 8. Steady
        var moving = false
        if let rate = input.rotationRate, rate > t.maxRotationRate { moving = true }
        if let prev = input.previousJoints {
            let keys: [BodyJoint] = [.neck, .leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftAnkle, .rightAnkle]
            let deltas = keys.compactMap { k -> Double? in
                guard let a = p(k), let b = prev[k], b.confidence >= t.minJointConfidence else { return nil }
                return hypot((a.x - b.location.x) * aspect, a.y - b.location.y)
            }
            if !deltas.isEmpty, deltas.reduce(0, +) / Double(deltas.count) > t.maxJointMovement { moving = true }
        }
        checks.append(.init(kind: .steady, passed: !moving, message: moving ? "Hold still for a moment." : "Holding still."))

        let weights: [QualityCheck.Kind: Double] = [.person: 3, .fullBody: 3, .distance: 2, .pose: 2, .lighting: 1.5, .phoneAngle: 1.5, .centered: 1, .steady: 1]
        let total = checks.reduce(0) { $0 + (weights[$1.kind] ?? 1) }
        let passed = checks.filter(\.passed).reduce(0) { $0 + (weights[$1.kind] ?? 1) }
        return FrameQualityReport(checks: checks, score: total > 0 ? passed / total : 0)
    }

    static func midpoint(_ a: NormalizedPoint?, _ b: NormalizedPoint?) -> NormalizedPoint? {
        guard let a, let b else { return nil }
        return NormalizedPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// Angle of segment a→b from straight down, in degrees, using square-pixel coordinates.
    static func angleFromVertical(_ a: NormalizedPoint, _ b: NormalizedPoint, aspect: Double) -> Double {
        let dx = (b.x - a.x) * aspect
        let dy = b.y - a.y
        return atan2(abs(dx), dy) * 180 / .pi
    }

    static func poseCheck(view: CaptureView, p: (BodyJoint) -> NormalizedPoint?, aspect: Double,
                          headTop: Double?, feetY: Double?) -> QualityCheck {
        guard let ls = p(.leftShoulder), let rs = p(.rightShoulder) ?? p(.leftShoulder),
              let top = headTop, let feet = feetY, feet > top else {
            return .init(kind: .pose, passed: false, message: "Stand facing as instructed so your shoulders and hips are visible.")
        }
        let bodyHeight = feet - top
        let shoulderSpan = hypot((ls.x - rs.x) * aspect, ls.y - rs.y) / bodyHeight

        switch view {
        case .front, .back:
            if shoulderSpan < 0.14 {
                return .init(kind: .pose, passed: false, message: view == .front ? "Turn to face the camera directly." : "Turn so your back faces the camera directly.")
            }
            if abs(ls.y - rs.y) / bodyHeight > 0.03 {
                return .init(kind: .pose, passed: false, message: "Relax your shoulders and stand straight.")
            }
            for (s, w) in [(p(.leftShoulder), p(.leftWrist)), (p(.rightShoulder), p(.rightWrist))] {
                guard let s, let w else {
                    return .init(kind: .pose, passed: false, message: "Keep both hands visible, slightly away from your body.")
                }
                let angle = angleFromVertical(s, w, aspect: aspect)
                if angle < 8 {
                    return .init(kind: .pose, passed: false, message: "Move your arms slightly away from your body.")
                }
                if angle > 45 {
                    return .init(kind: .pose, passed: false, message: "Lower your arms a little — about a hand’s width from your sides.")
                }
            }
            if let lh = p(.leftHip), let rh = p(.rightHip), let la = p(.leftAnkle), let ra = p(.rightAnkle) {
                let hipW = abs(lh.x - rh.x)
                let ankleW = abs(la.x - ra.x)
                if ankleW < hipW * 0.5 {
                    return .init(kind: .pose, passed: false, message: "Place your feet about hip-width apart.")
                }
                if ankleW > hipW * 2.2 {
                    return .init(kind: .pose, passed: false, message: "Bring your feet a little closer together, about hip-width apart.")
                }
            }
            return .init(kind: .pose, passed: true, message: "Pose looks good.")
        case .side:
            if shoulderSpan > 0.09 {
                return .init(kind: .pose, passed: false, message: "Turn further so your side faces the camera.")
            }
            return .init(kind: .pose, passed: true, message: "Side pose looks good.")
        }
    }
}

/// Picks the best frames from a burst using quality scores.
public enum FrameSelector {
    /// Returns indices of up to `count` frames with the highest score, ignoring frames below `minimumScore`.
    public static func bestIndices(scores: [Double], count: Int, minimumScore: Double = 0.8) -> [Int] {
        scores.enumerated()
            .filter { $0.element >= minimumScore }
            .sorted { $0.element > $1.element }
            .prefix(count)
            .map(\.offset)
            .sorted()
    }
}
