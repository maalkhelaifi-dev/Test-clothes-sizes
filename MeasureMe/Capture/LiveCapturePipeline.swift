import AVFoundation
import Vision
import MeasureMeCore

/// Background frame processing: throttled live pose analysis, quality checks and burst collection.
/// Runs on the camera's output queue; results are delivered through `onReport`.
final class LiveCapturePipeline: @unchecked Sendable {

    struct LiveResult {
        let report: FrameQualityReport
        let joints: [BodyJoint: DetectedJoint]
        /// Width / height of the analysed frame.
        let imageAspect: Double
    }

    /// Called on the camera output queue after each analysed frame.
    var onResult: ((LiveResult) -> Void)?

    private let motion: MotionMonitor
    private let poseRequest = VNDetectHumanBodyPoseRequest()
    private let lock = NSLock()

    // Guarded by `lock`.
    private var expectedView: CaptureView = .front
    private var collecting = false
    private var candidates: [CapturedFrame] = []
    private var keepDepthForVision = false
    private var resetHistory = false

    // Output-queue only.
    private var lastAnalysis = Date.distantPast
    private var previousJoints: [BodyJoint: DetectedJoint]?

    static let analysisInterval: TimeInterval = 0.15
    static let maxCandidates = 6
    static let minimumCandidateScore = 0.85

    init(motion: MotionMonitor) {
        self.motion = motion
    }

    func setExpectedView(_ view: CaptureView) {
        lock.lock(); expectedView = view; resetHistory = true; lock.unlock()
    }

    func setKeepsDepthForVision(_ keep: Bool) {
        lock.lock(); keepDepthForVision = keep; lock.unlock()
    }

    func beginCollecting() {
        lock.lock(); candidates = []; collecting = true; lock.unlock()
    }

    /// Stops collecting and returns the gathered candidate frames.
    func endCollecting() -> [CapturedFrame] {
        lock.lock(); defer { lock.unlock() }
        collecting = false
        let result = candidates
        candidates = []
        return result
    }

    func process(_ frame: CameraService.Frame) {
        let now = Date()
        guard now.timeIntervalSince(lastAnalysis) >= Self.analysisInterval else { return }
        lastAnalysis = now

        lock.lock()
        let view = expectedView
        let isCollecting = collecting
        let keepDepth = keepDepthForVision
        if resetHistory { previousJoints = nil; resetHistory = false }
        lock.unlock()

        let pb = frame.pixelBuffer
        let handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        var joints: [BodyJoint: DetectedJoint] = [:]
        var people = 0
        if (try? handler.perform([poseRequest])) != nil, let results = poseRequest.results {
            people = VisionConversions.personCount(results)
            if let person = VisionConversions.mostProminent(results) {
                joints = VisionConversions.joints(from: person)
            }
        }

        let width = Double(CVPixelBufferGetWidth(pb)), height = Double(CVPixelBufferGetHeight(pb))
        let m = motion.snapshot()
        let input = FrameQualityInput(
            expectedView: view, joints: joints, personCount: people,
            imageAspect: width / max(height, 1),
            meanLuma: PixelBufferUtils.meanLuma(pb),
            devicePitchDegrees: m?.pitchDegrees, deviceRollDegrees: m?.rollDegrees, rotationRate: m?.rotationRate,
            previousJoints: previousJoints)
        let report = FrameQualityEvaluator.evaluate(input)
        previousJoints = joints

        if isCollecting, report.score >= Self.minimumCandidateScore, let copy = PixelBufferUtils.copy(pb) {
            let depthScale = frame.depthData.flatMap {
                DepthScale.cmPerImagePixel(depthData: $0, imageSize: CGSize(width: width, height: height))
            }
            let depthForVision = keepDepth ? frame.depthData?.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32) : nil
            let captured = CapturedFrame(view: view, pixelBuffer: copy, depthForVision: depthForVision,
                                         depthCMPerImagePixel: depthScale, qualityScore: report.score, liveJoints: joints)
            lock.lock()
            if collecting {
                candidates.append(captured)
                if candidates.count > Self.maxCandidates {
                    // Drop the weakest frame.
                    if let worst = candidates.indices.min(by: { candidates[$0].qualityScore < candidates[$1].qualityScore }) {
                        candidates.remove(at: worst)
                    }
                }
            }
            lock.unlock()
        }

        onResult?(LiveResult(report: report, joints: joints, imageAspect: width / max(height, 1)))
    }
}
