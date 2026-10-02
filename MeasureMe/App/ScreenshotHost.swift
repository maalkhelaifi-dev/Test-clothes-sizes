#if DEBUG
import SwiftUI
import MeasureMeCore

/// Debug-only screenshot mode for documentation. Launch with `-screenshotScene <name>`.
/// Uses a throwaway data folder and sample data; real user data is never touched.
enum ScreenshotScene: String, CaseIterable {
    case welcome, privacy, consent, profiles, profileEditor, profileDetail, category, setup, capture,
         results, recommendation, charts, chartDetail, chartEditor, history, settings

    static func fromLaunchArguments() -> ScreenshotScene? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-screenshotScene"), i + 1 < args.count else { return nil }
        return ScreenshotScene(rawValue: args[i + 1])
    }
}

@MainActor
struct ScreenshotHost: View {
    let scene: ScreenshotScene
    @State private var fixture = ScreenshotFixture()

    var body: some View {
        content
            .environment(fixture.model)
            .environment(fixture.model.settings)
    }

    @ViewBuilder
    private var content: some View {
        let model = fixture.model
        let profile = fixture.profile
        switch scene {
        case .welcome: WelcomeView(initialStep: 0)
        case .privacy: WelcomeView(initialStep: 2)
        case .consent: WelcomeView(initialStep: 3)
        case .profiles: MainTabView()
        case .profileEditor: ProfileEditorView(existing: profile)
        case .profileDetail: NavigationStack { ProfileDetailView(profileID: profile.id) }
        case .category: NavigationStack { CategorySelectionView(flow: fixture.flow, onClose: {}) }
        case .setup: NavigationStack { CaptureSetupView(flow: fixture.flow) }
        case .capture: CaptureIllustration()
        case .results: NavigationStack { MeasurementResultsView(flow: fixture.resultsFlow, onDone: {}) }
        case .recommendation:
            NavigationStack { RecommendationView(profileID: profile.id, initialCategory: .tops, initialFit: .regular) }
        case .charts:
            TabView {
                SizeChartListView().tabItem { Label("Size charts", systemImage: "tablecells") }
            }
        case .chartDetail:
            NavigationStack { SizeChartDetailView(chartID: model.demoCharts.first { $0.category == .dresses }?.id ?? UUID()) }
        case .chartEditor: SizeChartEditorView(existing: nil)
        case .history:
            NavigationStack { SessionDetailView(profileID: profile.id, sessionID: profile.sessions[0].id) }
        case .settings:
            TabView {
                SettingsView().tabItem { Label("Privacy & settings", systemImage: "lock.shield") }
            }
        }
    }
}

/// Sample profile and estimates used only for screenshots.
@MainActor
final class ScreenshotFixture {
    let model: AppModel
    let profile: PersonProfile
    let flow: MeasureFlowModel
    let resultsFlow: MeasureFlowModel

    init() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MeasureMeScreenshots", isDirectory: true)
        let store = LocalStore(directory: dir)
        try? store.deleteEverything()
        let defaults = UserDefaults(suiteName: "MeasureMeScreenshots") ?? .standard
        defaults.removePersistentDomain(forName: "MeasureMeScreenshots")
        let settings = AppSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        settings.cameraConsentGiven = true
        settings.defaultUnit = .centimetres
        model = AppModel(settings: settings, store: store)

        let estimation = Self.sampleEstimation()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let session = MeasurementSession(
            date: date, category: .shirts, method: .mixed,
            measurements: estimation.measurementSet(capturedAt: date)
                .merging(MeasurementSet([.manual(.wrist, cm: 17, at: date)])),
            captureSummary: CaptureSummary(viewsCaptured: ["Front", "Side"], usedDepth: false,
                                           lensDescription: "Rear wide camera", overallQuality: 0.96, notes: []))
        var p = PersonProfile(displayName: "Alex (sample)", heightCM: 172, preferredUnit: .centimetres,
                              defaultFit: .regular, preferredAudiences: [.unisex, .mens], adultConfirmed: true,
                              createdAt: date, sessions: [session])
        try? model.save(profile: p)
        p = model.profile(id: p.id) ?? p
        profile = p

        flow = MeasureFlowModel(profile: p, mode: .camera)
        flow.category = .shirts

        resultsFlow = MeasureFlowModel(profile: p, mode: .camera)
        resultsFlow.category = .shirts
        resultsFlow.selectedKinds.insert(.wrist)
        resultsFlow.estimation = estimation
        resultsFlow.measurements = estimation.measurementSet()
    }

    static func sampleEstimation() -> EstimationResult {
        func e(_ k: MeasurementKind, _ v: Double, _ c: ConfidenceLevel, _ u: Double, _ m: String) -> MeasurementEstimate {
            MeasurementEstimate(kind: k, valueCM: v, confidence: c, uncertaintyCM: u, method: m, unavailableReason: nil)
        }
        let list: [MeasurementEstimate] = [
            e(.chest, 97.5, .medium, 4, "Ellipse from front width and side depth."),
            e(.waist, 83, .medium, 4, "Ellipse from front width and side depth."),
            e(.hips, 99, .medium, 4, "Ellipse from front width and side depth."),
            e(.neck, 39, .low, 4.8, "Rough ellipse at the base of the neck. Hair and collars affect this."),
            e(.shoulderWidth, 45.5, .medium, 2.5, "Distance between shoulder landmarks in the front view, scaled by your height."),
            e(.armLength, 61, .high, 2, "Shoulder → elbow → wrist landmarks in the front view."),
            e(.sleeveLength, 84, .medium, 3, "Half your shoulder width plus arm length."),
            e(.inseam, 80, .medium, 2.5, "Crotch gap to floor in the front outline, scaled by your height."),
            .unavailable(.wrist, MeasurementKind.wrist.cameraSupport.explanation),
        ]
        return EstimationResult(estimates: Dictionary(uniqueKeysWithValues: list.map { ($0.kind, $0) }),
                                warnings: ["Your arms seemed to touch your body at the hips / seat level, which makes it look wider. Hold your arms slightly further out and retake."],
                                framesUsed: 3)
    }
}

/// The live capture screen needs a real camera, so in the Simulator it is illustrated with the same
/// overlay components on a placeholder background.
@MainActor
struct CaptureIllustration: View {
    private let joints: [BodyJoint: DetectedJoint] = [
        .nose: .init(x: 0.5, y: 0.17, confidence: 0.9), .neck: .init(x: 0.5, y: 0.25, confidence: 0.9),
        .leftShoulder: .init(x: 0.41, y: 0.26, confidence: 0.9), .rightShoulder: .init(x: 0.59, y: 0.26, confidence: 0.9),
        .leftElbow: .init(x: 0.385, y: 0.38, confidence: 0.9), .rightElbow: .init(x: 0.615, y: 0.38, confidence: 0.9),
        .leftWrist: .init(x: 0.38, y: 0.49, confidence: 0.9), .rightWrist: .init(x: 0.62, y: 0.49, confidence: 0.9),
        .leftHip: .init(x: 0.45, y: 0.5, confidence: 0.9), .rightHip: .init(x: 0.55, y: 0.5, confidence: 0.9),
        .leftKnee: .init(x: 0.45, y: 0.66, confidence: 0.9), .rightKnee: .init(x: 0.55, y: 0.66, confidence: 0.9),
        .leftAnkle: .init(x: 0.44, y: 0.82, confidence: 0.9), .rightAnkle: .init(x: 0.56, y: 0.82, confidence: 0.9),
    ]

    var body: some View {
        let report = FrameQualityEvaluator.evaluate(FrameQualityInput(
            expectedView: .front, joints: joints, personCount: 1, imageAspect: 9.0 / 16.0,
            meanLuma: 0.5, devicePitchDegrees: 2, deviceRollDegrees: 1, rotationRate: 0))
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .top, endPoint: .bottom)
                BodyGuideOverlay(rect: rect, view: .front)
                SkeletonOverlay(joints: joints, rect: rect)
                VStack(spacing: 12) {
                    VStack(spacing: 8) {
                        Text("Front view · 1 of 2").font(.headline).foregroundStyle(.white)
                        ProgressView(value: 0, total: 2).tint(.white).frame(maxWidth: 220)
                        ChecklistView(report: report)
                        Label("Spoken guidance", systemImage: "speaker.wave.2")
                            .font(.footnote).foregroundStyle(.white)
                    }
                    .padding(12)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 50)
                    Spacer()
                    Text(report.primaryInstruction ?? "Hold still…")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                        .padding()
                        .padding(.bottom, 20)
                }
            }
        }
        .ignoresSafeArea()
    }
}
#endif
