import AVFoundation
import UIKit
import Vision
import MeasureMeCore

/// A frame kept in memory for analysis. It is never written to disk unless the user turned on photo saving.
final class CapturedFrame: Identifiable, @unchecked Sendable {
    let id = UUID()
    let view: CaptureView
    let pixelBuffer: CVPixelBuffer
    /// Depth for Vision 3D pose (only when the depth stream matches the video orientation).
    let depthForVision: AVDepthData?
    let depthCMPerImagePixel: Double?
    let qualityScore: Double
    let liveJoints: [BodyJoint: DetectedJoint]

    init(view: CaptureView, pixelBuffer: CVPixelBuffer, depthForVision: AVDepthData?, depthCMPerImagePixel: Double?,
         qualityScore: Double, liveJoints: [BodyJoint: DetectedJoint]) {
        self.view = view
        self.pixelBuffer = pixelBuffer
        self.depthForVision = depthForVision
        self.depthCMPerImagePixel = depthCMPerImagePixel
        self.qualityScore = qualityScore
        self.liveJoints = liveJoints
    }

    lazy var thumbnail: UIImage? = PixelBufferUtils.uiImage(pixelBuffer)
}

/// Runs the heavier, accurate Vision requests on selected frames:
/// person segmentation (silhouette), 2D body pose and 3D body pose.
///
/// - VNGeneratePersonSegmentationRequest (iOS 15) — https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest
/// - VNDetectHumanBodyPoseRequest (iOS 14) — https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest
/// - VNDetectHumanBodyPose3DRequest (iOS 17) — https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest
/// - VNHumanBodyPose3DObservation.bodyHeight — https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation/bodyheight
enum BodyAnalysisService {

    enum AnalysisError: LocalizedError {
        case noPerson(CaptureView)
        case multiplePeople(CaptureView)

        var errorDescription: String? {
            switch self {
            case .noPerson(let v): return "No person was found in the \(v.displayName.lowercased()) photo."
            case .multiplePeople(let v): return "More than one person was found in the \(v.displayName.lowercased()) photo."
            }
        }
    }

    static func analyze(_ frame: CapturedFrame) throws -> ViewObservation {
        let pb = frame.pixelBuffer
        let handler: VNImageRequestHandler
        if let depth = frame.depthForVision {
            handler = VNImageRequestHandler(cvPixelBuffer: pb, depthData: depth, orientation: .up, options: [:])
        } else {
            handler = VNImageRequestHandler(cvPixelBuffer: pb, orientation: .up, options: [:])
        }

        let segmentation = VNGeneratePersonSegmentationRequest()
        segmentation.qualityLevel = .accurate
        segmentation.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let pose = VNDetectHumanBodyPoseRequest()
        try handler.perform([segmentation, pose])

        let poses = pose.results ?? []
        if VisionConversions.personCount(poses) > 1 { throw AnalysisError.multiplePeople(frame.view) }
        guard let person = VisionConversions.mostProminent(poses) else { throw AnalysisError.noPerson(frame.view) }
        let joints = VisionConversions.joints(from: person)

        let mask = segmentation.results?.first.map { silhouette(from: $0.pixelBuffer) } ?? nil

        // 3D pose is optional evidence; failures are ignored.
        var height3D: Double?
        var measured = false
        let pose3D = VNDetectHumanBodyPose3DRequest()
        if (try? handler.perform([pose3D])) != nil, let obs = pose3D.results?.first {
            height3D = Double(obs.bodyHeight) * 100
            measured = obs.heightEstimation == .measured
        }

        return ViewObservation(
            view: frame.view,
            imageWidth: CVPixelBufferGetWidth(pb),
            imageHeight: CVPixelBufferGetHeight(pb),
            joints: joints,
            mask: mask,
            depthCMPerImagePixel: frame.depthCMPerImagePixel,
            pose3DBodyHeightCM: height3D,
            pose3DHeightIsMeasured: measured,
            frameQuality: frame.qualityScore)
    }

    /// Copies a one-component 8-bit Vision mask into a `SilhouetteMask`.
    static func silhouette(from pb: CVPixelBuffer) -> SilhouetteMask? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        var data = [UInt8](repeating: 0, count: w * h)
        let src = base.assumingMemoryBound(to: UInt8.self)
        data.withUnsafeMutableBufferPointer { dst in
            for y in 0..<h {
                for x in 0..<w { dst[y * w + x] = src[y * rowBytes + x] }
            }
        }
        return SilhouetteMask(width: w, height: h, data: data)
    }

    /// Analyses all frames and estimates measurements. Runs off the main thread.
    static func estimate(frames: [CaptureView: [CapturedFrame]], heightCM: Double,
                         requested: [MeasurementKind]) async -> (EstimationResult, [String]) {
        await Task.detached(priority: .userInitiated) {
            var problems: [String] = []
            var observations: [CaptureView: [ViewObservation]] = [:]
            for (view, list) in frames {
                for frame in list {
                    do {
                        observations[view, default: []].append(try analyze(frame))
                    } catch {
                        let message = error.localizedDescription
                        if !problems.contains(message) { problems.append(message) }
                    }
                }
            }
            let result = MeasurementEstimator.estimate(
                heightCM: heightCM,
                fronts: observations[.front] ?? [],
                sides: observations[.side] ?? [],
                backs: observations[.back] ?? [],
                requested: requested)
            return (result, problems)
        }.value
    }
}
