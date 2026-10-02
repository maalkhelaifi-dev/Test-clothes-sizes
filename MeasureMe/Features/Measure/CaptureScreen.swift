import AVFoundation
import SwiftUI
import MeasureMeCore

/// Screen 4 (part 2): live camera with positioning guidance, quality checks and automatic capture.
@MainActor
struct CaptureScreen: View {
    @Bindable var flow: MeasureFlowModel
    @Environment(AppSettings.self) private var settings
    @Environment(\.openURL) private var openURL
    @State private var coordinator: CaptureCoordinator?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let coordinator {
                CameraPreview(layer: coordinator.camera.previewLayer)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                GeometryReader { geo in
                    let rect = fittedRect(in: geo.size, aspect: coordinator.imageAspect)
                    BodyGuideOverlay(rect: rect, view: coordinator.currentView ?? .front)
                    SkeletonOverlay(joints: coordinator.joints, rect: rect)
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)
                overlay(coordinator)
            } else {
                ProgressView().tint(.white)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .statusBarHidden()
        .onAppear(perform: start)
        .onDisappear {
            coordinator?.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func start() {
        guard coordinator == nil else { return }
        let views = flow.pendingViews.isEmpty ? flow.requiredViews : flow.pendingViews
        let c = CaptureCoordinator(views: views, useFrontCamera: flow.useFrontCamera,
                                   wantDepth: settings.useDepthWhenAvailable, voiceGuidance: settings.voiceGuidance)
        coordinator = c
        UIApplication.shared.isIdleTimerDisabled = true
        Task { await c.start() }
    }

    private func finish(_ c: CaptureCoordinator) {
        flow.merge(captures: c.captured)
        if let config = c.configuration {
            flow.captureLens = config.lensDescription
            flow.usedDepth = config.usesDepth
        }
        if let i = flow.path.lastIndex(of: .review) {
            flow.path = Array(flow.path[...i])
        } else {
            if flow.path.last == .capture { flow.path.removeLast() }
            flow.path.append(.review)
        }
    }

    @ViewBuilder
    private func overlay(_ c: CaptureCoordinator) -> some View {
        VStack(spacing: 12) {
            // Top: step + checklist
            VStack(spacing: 8) {
                if let view = c.currentView {
                    Text("\(view.displayName) view · \(c.currentIndex + 1) of \(c.views.count)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    ProgressView(value: Double(c.currentIndex), total: Double(max(1, c.views.count)))
                        .tint(.white)
                        .frame(maxWidth: 220)
                        .accessibilityLabel("Capture progress, view \(c.currentIndex + 1) of \(c.views.count)")
                }
                if let report = c.report, c.phase == .positioning || isCountdown(c.phase) {
                    ChecklistView(report: report)
                }
                Toggle(isOn: Binding(get: { settings.voiceGuidance }, set: { settings.voiceGuidance = $0; c.setVoiceGuidance($0) })) {
                    Label("Spoken guidance", systemImage: "speaker.wave.2")
                }
                .toggleStyle(.button)
                .tint(.white)
                .font(.footnote)
            }
            .padding(12)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            .padding(.top, 8)

            Spacer()

            // Centre: countdown
            if case .countdown(let n) = c.phase {
                Text("\(n)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .accessibilityLabel("Capturing in \(n)")
            }

            Spacer()

            // Bottom: the main instruction
            VStack(spacing: 12) {
                Text(instruction(c))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.updatesFrequently)
                if let notice = c.notice {
                    Text(notice).font(.subheadline).foregroundStyle(.yellow)
                }
                switch c.phase {
                case .failed:
                    failureActions(c)
                case .finished:
                    Button("Review photos") { finish(c) }
                        .buttonStyle(.primary)
                default:
                    EmptyView()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            .padding()
        }
        .onChange(of: c.phase) { _, newPhase in
            if newPhase == .finished { finish(c) }
        }
    }

    private func isCountdown(_ phase: CaptureCoordinator.Phase) -> Bool {
        if case .countdown = phase { return true }
        return false
    }

    private func instruction(_ c: CaptureCoordinator) -> String {
        switch c.phase {
        case .idle, .starting: return "Starting camera…"
        case .positioning: return c.report?.primaryInstruction ?? (c.currentView?.instruction ?? "")
        case .countdown: return "Hold still…"
        case .capturing: return "Capturing — hold still"
        case .turning(let next): return "Great! Now: \(next.instruction)"
        case .finished: return "All photos captured."
        case .failed(let message): return message
        }
    }

    @ViewBuilder
    private func failureActions(_ c: CaptureCoordinator) -> some View {
        VStack(spacing: 10) {
            if c.permissionProblem, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }
                    .buttonStyle(.primary)
            }
            Button("Enter measurements manually instead") {
                flow.startManualEntry()
                flow.path = [.results]
            }
            .foregroundStyle(.white)
            .frame(minHeight: 44)
        }
    }

    /// Where the aspect-fit video sits inside the screen.
    private func fittedRect(in size: CGSize, aspect: Double) -> CGRect {
        guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
        let viewAspect = size.width / size.height
        if viewAspect > aspect {
            let w = size.height * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        } else {
            let h = size.width / aspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        }
    }
}

@MainActor
struct ChecklistView: View {
    let report: FrameQualityReport

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 110), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(report.checks) { check in
                Label(check.kind.displayName, systemImage: check.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(check.passed ? .green : .orange)
                    .accessibilityLabel("\(check.kind.displayName): \(check.passed ? "OK" : check.message)")
            }
        }
        .frame(maxWidth: 360)
    }
}

/// Dashed outline showing where to stand.
@MainActor
struct BodyGuideOverlay: View {
    let rect: CGRect
    let view: CaptureView

    var body: some View {
        let w = rect.width * (view == .side ? 0.3 : 0.5)
        let h = rect.height * 0.8
        RoundedRectangle(cornerRadius: w / 2)
            .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            .foregroundStyle(.white.opacity(0.6))
            .frame(width: w, height: h)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// Live joints from Vision, drawn over the preview.
@MainActor
struct SkeletonOverlay: View {
    let joints: [BodyJoint: DetectedJoint]
    let rect: CGRect

    private static let bones: [(BodyJoint, BodyJoint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip), (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle), (.neck, .nose),
    ]

    var body: some View {
        Canvas { context, _ in
            func point(_ j: BodyJoint) -> CGPoint? {
                guard let d = joints[j], d.confidence > 0.3 else { return nil }
                return CGPoint(x: rect.minX + d.location.x * rect.width, y: rect.minY + d.location.y * rect.height)
            }
            var path = Path()
            for (a, b) in Self.bones {
                if let p = point(a), let q = point(b) {
                    path.move(to: p)
                    path.addLine(to: q)
                }
            }
            context.stroke(path, with: .color(.cyan.opacity(0.8)), lineWidth: 3)
            for j in BodyJoint.allCases {
                if let p = point(j) {
                    context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(.white))
                }
            }
        }
    }
}

/// Hosts the AVCaptureVideoPreviewLayer.
struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    final class PreviewView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet {
                oldValue?.removeFromSuperlayer()
                if let previewLayer { layer.addSublayer(previewLayer) }
            }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer = layer
        return v
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer !== layer { uiView.previewLayer = layer }
    }
}
