import AVFoundation
import Observation
import MeasureMeCore

/// Drives the guided capture: positioning checks → countdown → short burst → best-frame selection → next view.
@MainActor
@Observable
final class CaptureCoordinator {

    enum Phase: Equatable {
        case idle
        case starting
        case positioning
        case countdown(Int)
        case capturing
        case turning(next: CaptureView)
        case finished
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    let views: [CaptureView]
    private(set) var currentIndex = 0
    private(set) var report: FrameQualityReport?
    private(set) var joints: [BodyJoint: DetectedJoint] = [:]
    /// Width / height of the video frames (used to place overlays on the preview).
    private(set) var imageAspect: Double = 9.0 / 16.0
    private(set) var captured: [CaptureView: [CapturedFrame]] = [:]
    private(set) var configuration: CameraService.Configuration?
    /// A transient message such as "Let's try again".
    private(set) var notice: String?
    /// True when the failure is a denied/restricted permission (so the UI can link to Settings).
    private(set) var permissionProblem = false

    var currentView: CaptureView? { currentIndex < views.count ? views[currentIndex] : nil }

    @ObservationIgnored let camera = CameraService()
    @ObservationIgnored private let motion = MotionMonitor()
    @ObservationIgnored private let pipeline: LiveCapturePipeline
    @ObservationIgnored private let speech = SpeechGuide()
    @ObservationIgnored private let position: AVCaptureDevice.Position
    @ObservationIgnored private let wantDepth: Bool
    @ObservationIgnored private var goodSince: Date?
    @ObservationIgnored private var badSince: Date?
    @ObservationIgnored private var flowTask: Task<Void, Never>?

    /// Seconds all checks must pass before the countdown starts.
    static let settleTime: TimeInterval = 1.0
    static let burstDuration: UInt64 = 1_600_000_000
    static let framesPerView = 3

    init(views: [CaptureView], useFrontCamera: Bool, wantDepth: Bool, voiceGuidance: Bool) {
        self.views = views
        self.position = useFrontCamera ? .front : .back
        self.wantDepth = wantDepth && !useFrontCamera
        self.pipeline = LiveCapturePipeline(motion: motion)
        speech.isEnabled = voiceGuidance
    }

    // MARK: Lifecycle

    func start() async {
        guard phase == .idle else { return }
        phase = .starting
        #if targetEnvironment(simulator)
        phase = .failed("The camera isn’t available in the iOS Simulator. Run on an iPhone, or enter measurements manually.")
        return
        #else
        do {
            try await CameraService.ensureAuthorized()
        } catch {
            permissionProblem = true
            phase = .failed(error.localizedDescription)
            return
        }
        do {
            let config = try await camera.configure(position: position, wantDepth: wantDepth)
            configuration = config
            pipeline.setKeepsDepthForVision(config.depthMatchesVideoOrientation)
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        camera.attachRotationCoordinator()
        let pipeline = self.pipeline
        pipeline.onResult = { @Sendable [weak self] result in
            Task { @MainActor [weak self] in self?.handle(result) }
        }
        camera.onFrame = { @Sendable frame in pipeline.process(frame) }
        motion.start()
        speech.activateAudioSession()
        camera.start()
        beginPositioning(announce: true)
        #endif
    }

    func stop() {
        flowTask?.cancel()
        flowTask = nil
        camera.onFrame = nil
        pipeline.onResult = nil
        camera.stop()
        motion.stop()
        speech.deactivateAudioSession()
    }

    func setVoiceGuidance(_ on: Bool) {
        speech.isEnabled = on
        if !on { speech.stop() }
    }

    // MARK: State machine

    private func beginPositioning(announce: Bool) {
        guard let view = currentView else { return }
        pipeline.setExpectedView(view)
        goodSince = nil
        badSince = nil
        phase = .positioning
        if announce { speech.say(view.instruction, force: true) }
    }

    private func handle(_ result: LiveCapturePipeline.LiveResult) {
        report = result.report
        joints = result.joints
        imageAspect = result.imageAspect
        switch phase {
        case .positioning:
            if result.report.allPassed {
                notice = nil
                if let since = goodSince {
                    if Date().timeIntervalSince(since) >= Self.settleTime { startCountdown() }
                } else {
                    goodSince = Date()
                }
            } else {
                goodSince = nil
                if let instruction = result.report.primaryInstruction { speech.say(instruction) }
            }
        case .countdown:
            if result.report.allPassed {
                badSince = nil
            } else if let since = badSince {
                if Date().timeIntervalSince(since) > 0.7 { abortCountdown() }
            } else {
                badSince = Date()
            }
        default:
            break
        }
    }

    private func startCountdown() {
        flowTask?.cancel()
        flowTask = Task { [weak self] in
            for n in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.phase = .countdown(n)
                self.speech.say("\(n)", force: true)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard let self, !Task.isCancelled else { return }
            await self.captureBurst()
        }
    }

    private func abortCountdown() {
        flowTask?.cancel()
        notice = "Hold still in position — let’s try again."
        speech.say("Hold still. Let's try again.", force: true)
        beginPositioning(announce: false)
    }

    private func captureBurst() async {
        guard let view = currentView else { return }
        phase = .capturing
        pipeline.beginCollecting()
        try? await Task.sleep(nanoseconds: Self.burstDuration)
        let candidates = pipeline.endCollecting()
        guard !Task.isCancelled else { return }

        let picked = FrameSelector.bestIndices(scores: candidates.map(\.qualityScore), count: Self.framesPerView,
                                               minimumScore: LiveCapturePipeline.minimumCandidateScore)
        guard !picked.isEmpty else {
            notice = "Couldn’t get a clear, steady frame. Let’s try again."
            speech.say("I couldn't get a clear photo. Let's try again.", force: true)
            beginPositioning(announce: false)
            return
        }
        captured[view] = picked.map { candidates[$0] }
        speech.say("Got it.", force: true)

        if currentIndex + 1 < views.count {
            currentIndex += 1
            let next = views[currentIndex]
            phase = .turning(next: next)
            pipeline.setExpectedView(next)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            speech.say(next.instruction, force: true)
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            beginPositioning(announce: false)
        } else {
            phase = .finished
            camera.onFrame = nil
            speech.say("All photos captured.", force: true)
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            stop()
        }
    }
}
