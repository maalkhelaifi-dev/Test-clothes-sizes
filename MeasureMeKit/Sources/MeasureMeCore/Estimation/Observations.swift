import Foundation

/// Body joints, mirroring Vision's `VNHumanBodyPoseObservation.JointName` so the core stays framework-free.
public enum BodyJoint: String, Codable, CaseIterable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case root
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle

    public static let head: [BodyJoint] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
}

/// A 2D point in normalised image coordinates: origin top-left, x right, y down, both 0…1.
public struct NormalizedPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct DetectedJoint: Codable, Equatable, Sendable {
    public var location: NormalizedPoint
    public var confidence: Double
    public init(location: NormalizedPoint, confidence: Double) {
        self.location = location
        self.confidence = confidence
    }
    public init(x: Double, y: Double, confidence: Double) {
        self.init(location: NormalizedPoint(x: x, y: y), confidence: confidence)
    }
}

/// The view the person presents to the camera.
public enum CaptureView: String, Codable, CaseIterable, Identifiable, Sendable {
    case front
    case side
    case back

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .front: return "Front"
        case .side: return "Side"
        case .back: return "Back"
        }
    }

    public var instruction: String {
        switch self {
        case .front: return "Face the camera. Stand straight, feet hip-width apart, arms held slightly away from your body."
        case .side: return "Turn 90° so your left or right side faces the camera. Stand straight, arms relaxed by your sides, looking ahead."
        case .back: return "Turn your back to the camera. Feet hip-width apart, arms held slightly away from your body."
        }
    }
}

/// Binary person mask (row-major, top-left origin). Values ≥ 128 are "person".
public struct SilhouetteMask: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let data: [UInt8]

    public init(width: Int, height: Int, data: [UInt8]) {
        precondition(data.count == width * height, "mask data size mismatch")
        self.width = width
        self.height = height
        self.data = data
    }

    @inline(__always)
    public func isPerson(_ x: Int, _ y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        return data[y * width + x] >= 128
    }

    public func count(row y: Int) -> Int {
        guard y >= 0, y < height else { return 0 }
        var n = 0
        for x in 0..<width where data[y * width + x] >= 128 { n += 1 }
        return n
    }

    /// First and last rows that contain the person (ignores rows with only a few stray pixels).
    public func verticalExtent() -> (top: Int, bottom: Int)? {
        let minPixels = max(2, width / 200)
        var top: Int?
        var bottom: Int?
        for y in 0..<height where count(row: y) >= minPixels {
            if top == nil { top = y }
            bottom = y
        }
        guard let t = top, let b = bottom, b > t else { return nil }
        return (t, b)
    }

    /// All horizontal runs of person pixels in a row as half-open column ranges.
    public func runs(row y: Int) -> [Range<Int>] {
        guard y >= 0, y < height else { return [] }
        var result: [Range<Int>] = []
        var start: Int?
        for x in 0..<width {
            if data[y * width + x] >= 128 {
                if start == nil { start = x }
            } else if let s = start {
                result.append(s..<x)
                start = nil
            }
        }
        if let s = start { result.append(s..<width) }
        return result
    }

    /// The run containing column `x`, or the nearest run within `searchRadius` columns.
    public func run(row y: Int, containing x: Int, searchRadius: Int = 3) -> Range<Int>? {
        let rs = runs(row: y)
        if let r = rs.first(where: { $0.contains(x) }) { return r }
        let near = rs.map { r -> (Range<Int>, Int) in
            let d = x < r.lowerBound ? r.lowerBound - x : x - (r.upperBound - 1)
            return (r, d)
        }.filter { $0.1 <= searchRadius }.min { $0.1 < $1.1 }
        return near?.0
    }

    /// The widest run in a row.
    public func widestRun(row y: Int) -> Range<Int>? {
        runs(row: y).max { $0.count < $1.count }
    }

    /// Median run width (containing `x`) over rows `y-radius ... y+radius` — reduces mask noise.
    public func medianWidth(row y: Int, containing x: Int, radius: Int = 2) -> (width: Double, run: Range<Int>)? {
        var samples: [(Int, Range<Int>)] = []
        for yy in (y - radius)...(y + radius) {
            if let r = run(row: yy, containing: x) { samples.append((r.count, r)) }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort { $0.0 < $1.0 }
        let mid = samples[samples.count / 2]
        return (Double(mid.0), mid.1)
    }

    public func medianWidestWidth(row y: Int, radius: Int = 2) -> Double? {
        var samples: [Int] = []
        for yy in (y - radius)...(y + radius) {
            if let r = widestRun(row: yy) { samples.append(r.count) }
        }
        guard !samples.isEmpty else { return nil }
        samples.sort()
        return Double(samples[samples.count / 2])
    }

    /// Scans down from `fromRow` to `toRow` for the first row where column `centerX` is background
    /// while there is body on both sides — the gap between the legs (crotch).
    public func crotchRow(centerX: Int, fromRow: Int, toRow: Int) -> Int? {
        guard fromRow < toRow else { return nil }
        var consecutive = 0
        for y in max(0, fromRow)...min(height - 1, toRow) {
            let gap = !isPerson(centerX, y) && !isPerson(centerX - 1, y) && !isPerson(centerX + 1, y)
            let rs = runs(row: y)
            let left = rs.contains { $0.upperBound <= centerX }
            let right = rs.contains { $0.lowerBound > centerX }
            if gap && left && right {
                consecutive += 1
                // Require a few consecutive rows so a single noisy row doesn't count.
                if consecutive >= 3 { return y - 2 }
            } else {
                consecutive = 0
            }
        }
        return nil
    }
}

/// Everything the estimator needs from one analysed frame of one view.
public struct ViewObservation: Sendable {
    public var view: CaptureView
    public var imageWidth: Int
    public var imageHeight: Int
    /// Joints in normalised top-left image coordinates.
    public var joints: [BodyJoint: DetectedJoint]
    /// Person mask covering the full image (any resolution).
    public var mask: SilhouetteMask?
    /// Centimetres per image pixel at the body, from LiDAR depth + camera intrinsics, when available.
    public var depthCMPerImagePixel: Double?
    /// Body height from Vision 3D pose (cm), when available.
    public var pose3DBodyHeightCM: Double?
    /// True when the 3D height was measured using depth (rather than a reference default).
    public var pose3DHeightIsMeasured: Bool
    /// 0…1 quality of the frame from live checks.
    public var frameQuality: Double

    public init(view: CaptureView, imageWidth: Int, imageHeight: Int, joints: [BodyJoint: DetectedJoint],
                mask: SilhouetteMask?, depthCMPerImagePixel: Double? = nil, pose3DBodyHeightCM: Double? = nil,
                pose3DHeightIsMeasured: Bool = false, frameQuality: Double = 1) {
        self.view = view
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.joints = joints
        self.mask = mask
        self.depthCMPerImagePixel = depthCMPerImagePixel
        self.pose3DBodyHeightCM = pose3DBodyHeightCM
        self.pose3DHeightIsMeasured = pose3DHeightIsMeasured
        self.frameQuality = frameQuality
    }

    /// Joint if detected with at least `minConfidence`.
    public func joint(_ j: BodyJoint, minConfidence: Double = 0.3) -> NormalizedPoint? {
        guard let d = joints[j], d.confidence >= minConfidence else { return nil }
        return d.location
    }
}
