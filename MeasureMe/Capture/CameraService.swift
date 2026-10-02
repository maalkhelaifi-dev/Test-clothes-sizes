import AVFoundation
import UIKit

/// Owns the AVCaptureSession. Delivers portrait-oriented video frames (and LiDAR depth when enabled)
/// on a background queue. Frames are never written to disk by this class.
///
/// APIs:
/// - AVCaptureVideoDataOutput — https://developer.apple.com/documentation/avfoundation/avcapturevideodataoutput
/// - AVCaptureDepthDataOutput — https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput
/// - AVCaptureDataOutputSynchronizer — https://developer.apple.com/documentation/avfoundation/avcapturedataoutputsynchronizer
/// - AVCaptureDevice.RotationCoordinator (iOS 17) — https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator
/// - AVCaptureConnection.videoRotationAngle (iOS 17) — https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle
final class CameraService: NSObject, @unchecked Sendable {

    enum CameraError: LocalizedError, Equatable {
        case permissionDenied
        case permissionRestricted
        case noSuitableCamera
        case configurationFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Camera access is turned off for Measure Me. You can turn it on in Settings › Privacy & Security › Camera, or enter your measurements manually."
            case .permissionRestricted:
                return "Camera access is restricted on this device (for example by Screen Time or a device policy). You can still enter measurements manually."
            case .noSuitableCamera:
                return "No suitable camera was found on this device. You can still enter measurements manually."
            case .configurationFailed(let reason):
                return "The camera could not be started: \(reason)"
            }
        }
    }

    struct Frame {
        let pixelBuffer: CVPixelBuffer
        let depthData: AVDepthData?
        let timestamp: CMTime
    }

    struct Configuration: Equatable {
        let lensDescription: String
        let usesDepth: Bool
        /// True when the depth stream is rotated to match the portrait video, so it can be passed to Vision.
        let depthMatchesVideoOrientation: Bool
        let position: AVCaptureDevice.Position
    }

    let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "MeasureMe.camera.session")
    private let outputQueue = DispatchQueue(label: "MeasureMe.camera.output", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private(set) var device: AVCaptureDevice?

    /// Called on a background queue for every delivered frame. Set before `start()`.
    var onFrame: ((Frame) -> Void)?

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspect
        super.init()
    }

    // MARK: Permission

    static func ensureAuthorized() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { return }
            throw CameraError.permissionDenied
        case .denied:
            throw CameraError.permissionDenied
        case .restricted:
            throw CameraError.permissionRestricted
        @unknown default:
            throw CameraError.permissionDenied
        }
    }

    // MARK: Configuration

    /// Selects a lens and configures outputs. Never picks the ultra-wide camera or a virtual multi-camera
    /// device (those can silently switch to the ultra-wide lens at close range and distort the outline).
    func configure(position: AVCaptureDevice.Position, wantDepth: Bool) async throws -> Configuration {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Configuration, Error>) in
            sessionQueue.async {
                do {
                    cont.resume(returning: try self.configureOnQueue(position: position, wantDepth: wantDepth))
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func configureOnQueue(position: AVCaptureDevice.Position, wantDepth: Bool) throws -> Configuration {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }
        synchronizer = nil

        var chosen: AVCaptureDevice?
        var usesDepth = false
        if position == .back, wantDepth,
           let lidar = AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) {
            chosen = lidar
            usesDepth = true
        }
        if chosen == nil {
            chosen = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        }
        guard let device = chosen else { throw CameraError.noSuitableCamera }
        self.device = device

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.configurationFailed(error.localizedDescription)
        }
        guard session.canAddInput(input) else { throw CameraError.configurationFailed("camera input unavailable") }
        session.addInput(input)

        if usesDepth {
            usesDepth = configureDepthFormat(device)
        }
        if !usesDepth {
            session.sessionPreset = session.canSetSessionPreset(.hd1920x1080) ? .hd1920x1080 : .high
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(videoOutput) else { throw CameraError.configurationFailed("video output unavailable") }
        session.addOutput(videoOutput)

        var depthRotated = false
        if usesDepth, session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
            depthOutput.alwaysDiscardsLateDepthData = true
            if let conn = depthOutput.connection(with: .depthData), conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
                depthRotated = true
            }
            videoOutput.setSampleBufferDelegate(nil, queue: nil)
            let sync = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
            sync.setDelegate(self, queue: outputQueue)
            synchronizer = sync
        } else {
            usesDepth = false
            videoOutput.setSampleBufferDelegate(self, queue: outputQueue)
        }

        if let conn = videoOutput.connection(with: .video) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            if position == .front, conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = false
            }
        }

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
            // Keep the native field of view: no digital zoom.
            device.videoZoomFactor = 1
            device.unlockForConfiguration()
        } catch {
            // Non-fatal: defaults still work.
        }

        let lens: String
        if position == .back {
            lens = usesDepth ? "Rear wide camera with LiDAR depth" : "Rear wide camera"
        } else {
            lens = "Front camera (lower accuracy)"
        }
        return Configuration(lensDescription: lens, usesDepth: usesDepth,
                             depthMatchesVideoOrientation: usesDepth && depthRotated, position: position)
    }

    /// Picks a video format with LiDAR depth support close to 1920 px wide and the largest depth map.
    private func configureDepthFormat(_ device: AVCaptureDevice) -> Bool {
        let candidates = device.formats.filter { f in
            !f.supportedDepthDataFormats.isEmpty
                && CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        guard let format = candidates.min(by: { a, b in
            let wa = CMVideoFormatDescriptionGetDimensions(a.formatDescription).width
            let wb = CMVideoFormatDescriptionGetDimensions(b.formatDescription).width
            return abs(Int(wa) - 1920) < abs(Int(wb) - 1920)
        }) else { return false }
        let depthFormats = format.supportedDepthDataFormats.filter {
            let t = CMFormatDescriptionGetMediaSubType($0.formatDescription)
            return t == kCVPixelFormatType_DepthFloat32 || t == kCVPixelFormatType_DepthFloat16
        }
        guard let depthFormat = depthFormats.max(by: {
            CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width
        }) else { return false }
        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.activeDepthDataFormat = depthFormat
            device.unlockForConfiguration()
            return true
        } catch {
            return false
        }
    }

    /// Keeps the preview upright using the rotation coordinator. Call on the main thread after `configure`.
    @MainActor
    func attachRotationCoordinator() {
        guard let device else { return }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] c, _ in
            let angle = c.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async { self?.applyPreviewRotation(angle) }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        if let conn = previewLayer.connection, conn.isVideoRotationAngleSupported(angle) {
            conn.videoRotationAngle = angle
        }
    }

    // MARK: Running

    func start() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        rotationObservation = nil
        rotationCoordinator = nil
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(Frame(pixelBuffer: pb, depthData: nil, timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)))
    }
}

extension CameraService: AVCaptureDataOutputSynchronizerDelegate {
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        guard let video = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
              !video.sampleBufferWasDropped,
              let pb = CMSampleBufferGetImageBuffer(video.sampleBuffer) else { return }
        var depth: AVDepthData?
        if let d = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVCaptureSynchronizedDepthData,
           !d.depthDataWasDropped {
            depth = d.depthData
        }
        onFrame?(Frame(pixelBuffer: pb, depthData: depth, timestamp: CMSampleBufferGetPresentationTimeStamp(video.sampleBuffer)))
    }
}
