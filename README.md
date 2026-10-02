# Measure Me

A native iPhone app (Swift, SwiftUI, iOS 17+) that guides you through front and side photos, **estimates** body measurements on-device, shows how confident each estimate is, lets you correct every value, and maps the result onto brand size charts stored as data.

> Camera estimates are approximate. They are not a substitute for a tape measure or professional tailoring. The app says so on every results screen, and every value can be edited.

---

## Contents

- [Status: what is verified, what is not](#status-what-is-verified-what-is-not)
- [Implementation plan and assumptions](#implementation-plan-and-assumptions)
- [Architecture](#architecture)
- [Build and run](#build-and-run)
- [Device capabilities](#device-capabilities)
- [How measurements are estimated](#how-measurements-are-estimated)
- [Measurement limitations](#measurement-limitations)
- [Size charts and recommendations](#size-charts-and-recommendations)
- [Privacy and safety](#privacy-and-safety)
- [What still needs a trained model, device testing or verified data](#what-still-needs-a-trained-model-device-testing-or-verified-data)
- [Apple documentation used](#apple-documentation-used)

---

## Status: what is verified, what is not

| Part | Status |
|---|---|
| `MeasureMeKit` core package (units, measurement model, validation, size charts, recommender, estimator geometry, capture-quality rules) | **Compiled and tested**: 58 unit tests pass with `swift test` (Swift 6.1, Linux). |
| iOS app target (`MeasureMe/`: camera, Vision, SwiftUI screens) | **Written but not compiled by the author.** It was built in an environment without Xcode or an iPhone. The included GitHub Actions workflow builds it on macOS; run it there or in Xcode before relying on it. |
| Behaviour on a physical iPhone (camera, LiDAR, Vision accuracy, live checks) | **Not tested.** Needs a device. See [ACCURACY_TESTING.md](ACCURACY_TESTING.md). |
| Brand size charts | **Demo data only** (fictional brands, marked `DEMO DATA` everywhere). There are no real brand charts. |

## Implementation plan and assumptions

**Plan**
1. Keep all decision logic in a framework-free Swift package (`MeasureMeCore`) so it can be unit-tested anywhere: units, measurement model, validation, size-chart data model, recommender, silhouette geometry and frame-quality rules.
2. Keep Apple frameworks in thin adapters in the app: AVFoundation capture, Core Motion tilt, Vision pose and segmentation, LiDAR depth scale.
3. Guided capture: live checks every ~150 ms → 3-2-1 countdown → 1.6 s burst → keep the best 3 frames per view → front, side and optional back views.
4. Analysis on-device: person segmentation, 2D pose and 3D pose → estimator → editable results → saved session → recommendation.

**Assumptions**
- Deployment target **iOS 17.0** (needed for `VNDetectHumanBodyPose3DRequest`, `AVCaptureDevice.RotationCoordinator`, `videoRotationAngle` and the Observation framework). iPhone only, portrait only.
- The user enters their height; it is the scale reference.
- Adults only. A profile can't be saved unless you confirm the person is 18+.
- No real brand data is bundled. Demo brands are fictional and named "(Demo)".
- No networking at all. The app has no upload, sync or analytics code. Cloud features would need explicit opt-in and a separate design review.
- Bundle ID `com.example.MeasureMe`. Change it, and set your signing team, before installing on a device.

## Architecture

```
MeasureMeKit/                      Swift package — pure logic, Foundation only, fully unit-tested
  Sources/MeasureMeCore/
    Model/        Units, MeasurementKind (metadata, plausible ranges, camera support),
                  MeasurementValue/Set (cm, confidence, uncertainty, source, date),
                  MeasurementValidator, ClothingCategory + FitPreference, PersonProfile + MeasurementSession
    Sizing/       SizeChart (data model: body vs garment, region, audience, product line, source URL,
                  verified date, demo flag), SizeChartLibrary (lookup, import/export JSON),
                  SizeChartValidator, EaseGuidelines, SizeRecommender
    Estimation/   Observations (joints, SilhouetteMask, ViewObservation), MeasurementEstimator,
                  CaptureQuality (FrameQualityEvaluator, FrameSelector)
    Resources/    DemoSizeCharts.json (fictional demo data)
  Tests/MeasureMeCoreTests/   58 tests: units, validation, chart lookup/import, recommender,
                              estimator (synthetic silhouettes), live quality checks

MeasureMe/                         iOS app
  App/            MeasureMeApp (root, tabs), AppModel (profiles, charts, deletion), AppSettings
  Persistence/    LocalStore (JSON, file protection, excluded from backup), CapturePhotoStore (opt-in)
  Capture/        CameraCapabilities (runtime detection), CameraService (AVCaptureSession, lens choice,
                  LiDAR depth, synchronizer), MotionMonitor (tilt/shake), SpeechGuide (spoken prompts),
                  VisionConversions, LiveCapturePipeline (throttled live pose + checks + burst),
                  CaptureCoordinator (state machine), BodyAnalysisService (segmentation + 2D/3D pose),
                  PixelBufferUtils + DepthScale
  Features/       Onboarding, Profiles, Measure (category → setup → capture → review → results),
                  Sizing (recommendation, chart list/detail/editor), Settings (privacy, deletion, limitations)
```

Data flow:

```
Camera frames ──► LiveCapturePipeline ──► FrameQualityEvaluator (core) ──► CaptureCoordinator (UI state, voice)
                         │ (burst, best frames, in memory only)
                         ▼
                 BodyAnalysisService (Vision) ──► ViewObservation (core) ──► MeasurementEstimator (core)
                                                                                   │
                       MeasurementResultsView (edit, validate) ◄────────────────────┘
                                   │ save
                                   ▼
                     PersonProfile.sessions (JSON on device) ──► SizeRecommender (core) ◄── SizeChartLibrary (JSON)
```

### Main screens

| # | Screen | File |
|---|---|---|
| 1 | Welcome, adult notice, privacy, consent | `Features/Onboarding/WelcomeView.swift` |
| 2 | Person profile and height entry | `Features/Profiles/ProfileEditorView.swift` |
| 3 | Category, fit and which measurements to capture | `Features/Measure/CategorySelectionView.swift` |
| 4 | Guided camera setup and capture | `Features/Measure/CaptureSetupView.swift`, `CaptureScreen.swift` |
| 5 | Capture quality review and retake | `Features/Measure/CaptureReviewView.swift` |
| 6 | Results with confidence, uncertainty and manual editing | `Features/Measure/MeasurementResultsView.swift` |
| 7 | Brand and product size recommendation | `Features/Sizing/RecommendationView.swift` |
| 8 | Saved profiles and measurement history | `Features/Profiles/ProfilesListView.swift`, `ProfileDetailView.swift` |
| 9 | Size-chart management (add, update, import, export) | `Features/Sizing/SizeChartListView.swift`, `SizeChartEditorView.swift` |

## Build and run

### Requirements
- macOS with **Xcode 15.0 or later** (Xcode 16 recommended).
- An iPhone running **iOS 17 or later** for camera capture. The Simulator has no camera: the app runs there, but only manual entry, charts and recommendations work.

### Steps
1. Clone the repository and open `MeasureMe.xcodeproj` in Xcode. The local package `MeasureMeKit` resolves automatically.
2. Select the **MeasureMe** target, then **Signing & Capabilities**:
   - choose your **Team**;
   - change the **Bundle Identifier** (e.g. `com.yourname.MeasureMe`).
3. Connect your iPhone and select it as the run destination. Turn on Developer Mode on the iPhone if asked (Settings › Privacy & Security › Developer Mode).
4. Press **Run** (⌘R). The first time you start a capture, allow camera access.

### Command line

```bash
# Core logic tests (macOS or Linux, Swift 5.9+)
cd MeasureMeKit && swift test

# Build the app for the Simulator
xcodebuild build -project MeasureMe.xcodeproj -scheme MeasureMe \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO

# Core tests through the app scheme on a Simulator
xcodebuild test -project MeasureMe.xcodeproj -scheme MeasureMe \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

If you add or remove app source files outside Xcode, regenerate the project with `python3 scripts/generate_xcodeproj.py`, or use [XcodeGen](https://github.com/yonaskolb/XcodeGen) with `xcodegen generate` (`project.yml` is included).

### Using the app
1. Finish onboarding: confirm you are 18+, read the privacy notes, and choose whether to consent to camera use.
2. **Profiles › +**: enter a nickname and your height, measured barefoot.
3. Open the profile › **Measure with camera** (or **Enter measurements manually**).
4. Pick the clothing category and fit. Measurements are pre-selected for that category; you can change them.
5. Follow the setup advice. Prop the phone upright at waist height and stand 2–3 m away. A helper can hold it instead. Spoken guidance tells you what to fix, and the app captures automatically once every check passes.
6. Review the photos and retake any view, then tap **Estimate measurements**.
7. Correct anything you know is wrong, enter manual-only measurements, and **Save**.
8. **Find my size**: choose brand, category, region, chart line, size system, product line (optional) and fit.

## Device capabilities

The app detects hardware at runtime (`CameraCapabilities.detect()`) and shows the result in Camera setup and Settings.

| Capability | Detected | Used | Notes |
|---|---|---|---|
| Rear wide-angle camera | ✅ | ✅ **Default** | Least distortion for full-body photos. Zoom is fixed at 1×. |
| Rear ultra-wide camera | ✅ | ❌ Never | Barrel distortion bends outlines. Virtual multi-camera devices (dual-wide, triple) are also avoided because they can switch to ultra-wide automatically. |
| Front camera | ✅ | ⚠️ Optional fallback | Wider lens and usually lower quality. The app warns about lower accuracy. |
| LiDAR (`builtInLiDARDepthCamera`, Pro models) | ✅ | ✅ Optional cross-check | Median torso depth + intrinsics → cm/pixel, compared with the height-based scale; also fed to Vision 3D pose when the depth stream is rotated to match the video. It never replaces the entered height. Toggle in Settings. |
| Dual-camera disparity depth | ✅ | ❌ | Too noisy at 2–3 m. |
| TrueDepth (front) | ✅ | ❌ | Range too short for full-body capture. |
| ARKit scene depth / body tracking | ✅ | ❌ (reported only) | AVFoundation and ARKit can't share the camera. ARKit's skeleton is a fitted template, which adds no circumference information. Vision covers pose and outline. |
| Vision 2D pose (iOS 14+) | — | ✅ | Live checks and landmarks. |
| Vision person segmentation (iOS 15+) | — | ✅ | Body outline (widths, depths, crotch, extent). |
| Vision 3D pose (iOS 17+) | — | ✅ Cross-check | Its `bodyHeight` is compared with your height only when `heightEstimation == .measured` (that is, depth was used). |
| Core Motion device motion | ✅ | ✅ | Phone tilt and shake checks. No permission prompt is needed. |

Unsupported or degraded:
- **Simulator**: no camera, so the capture screen offers manual entry instead.
- **Camera permission denied or restricted**: a clear message, a button to open Settings, and manual entry.
- **No suitable camera**: the start button is disabled with an explanation, and manual entry is still available.

## How measurements are estimated

All of this happens in `MeasureMeCore/Estimation/MeasurementEstimator.swift` and is unit-tested with synthetic silhouettes.

1. **Scale.** User height ÷ the silhouette's vertical extent = cm per pixel. Mask and image resolutions may differ, and that is handled. If your head or feet touch the frame edge, scale confidence drops to low.
2. **Cross-checks.** LiDAR scale and Vision 3D height are compared with the height-based scale. A disagreement above 8% (LiDAR) or 6% (3D height) adds a warning and lowers confidence.
3. **Lengths** come from 2D landmarks:
   - shoulder width = shoulder-joint distance × 1.18 (Vision's joints sit inside the bony shoulder tip; the factor is uncalibrated);
   - arm length = shoulder → elbow → wrist;
   - sleeve = ½ shoulder width + arm;
   - inseam = crotch gap → floor, from the outline;
   - outseam = waist level → floor;
   - back length is a rough estimate.
4. **Torso girths** (chest, waist, hips) need **both front and side** views:
   - the front outline width is measured at landmark-relative levels (chest = widest band below the armpits, waist = narrowest, hips = widest above the crotch), using only the run of pixels connected to the body midline so separated arms are excluded;
   - the side outline depth is measured at the same fraction of stature;
   - circumference = Ramanujan ellipse perimeter × calibration factor.

   If the arms touch the torso, confidence becomes low and you get a warning. An optional back view cross-checks the width.
5. **Limb and neck girths** (neck, bicep, thigh, knee, calf) are rough ellipse or circle estimates and are **always low confidence**.
6. **Manual only, never estimated:** underbust, wrist, ankle, front shoulder-to-waist and rise. They aren't reliably observable through clothing at full-body distance.
7. **Several frames:** up to 3 frames per view are each estimated. The median is reported, and a wide frame-to-frame spread raises uncertainty and lowers confidence.
8. **Implausible results:** values outside the adult plausible range are discarded and marked unavailable. They are never shown as numbers.

## Measurement limitations

- **Not calibrated.** The geometric model is a principled first version. It has not been fitted against tape-measured volunteers, so expect errors of several centimetres on girths. Uncertainty bands (±4 cm for torso girths at medium confidence, wider at low) are engineering estimates, not measured error rates.
- **Ellipse model.** Real torso cross-sections aren't ellipses, so systematic bias per measurement is likely. `CalibrationProfile` exists so factors can be fitted later (see [ACCURACY_TESTING.md](ACCURACY_TESTING.md)).
- **Clothing, hair and posture** change the outline. Loose clothes inflate girths; hair affects neck and shoulder estimates; breathing and posture change the waist.
- **Perspective.** Camera height and distance cause small foreshortening. The live checks enforce upright, level framing, but don't remove it.
- **Landmark definitions.** Vision joints are joint centres, not the bony landmarks a tailor uses, so length definitions differ slightly.
- **Segmentation errors.** Busy backgrounds, low light or similar colours between clothes and wall degrade the outline.
- **Height accuracy.** Every estimate scales with the height you enter: a 2 cm height error is about a 1% error everywhere.

See **[ACCURACY_TESTING.md](ACCURACY_TESTING.md)** for how to test against tape-measure measurements.

## Size charts and recommendations

- **Charts are data** (`SizeChart`). Each records:
  - brand, and optionally a product line, collection or single garment;
  - category, region, chart line (unisex, womenswear or menswear, chosen by the user and never inferred) and size system;
  - **body vs garment** measurements, and for garment charts whether girths are full circumference or flat half-width;
  - sizes with ranges or single values;
  - **source URL, last-verified date and a demo flag**.
- **No fabricated data.** User charts can't be saved without an official source URL and a verification date, and can't claim to be demo data. Bundled demo charts are fictional, named "(Demo)", forced to `isDemoData = true` on load, and badged `DEMO DATA` in every view and recommendation.
- **Adding and updating charts:**
  - **Size charts › + › Add chart manually**, copying values from the brand's official guide;
  - **Import chart file (JSON)**, with values in cm or inches (format: [docs/SIZE_CHART_FORMAT.md](docs/SIZE_CHART_FORMAT.md));
  - **Mark as re-verified today** after re-checking;
  - **Export my charts** to share a file.
- **Product-specific charts** take priority over brand-wide ones. If none exists, the app says so and uses the brand-wide chart.
- **Recommender** (`SizeRecommender`):
  - for each size and measurement, a cost is computed: inside the range, it depends on where you sit relative to the fit preference; outside, 0.5 + distance ÷ tolerance, adjusted for fit;
  - costs are weighted by importance (primary 1.0, secondary 0.5);
  - garment charts are converted to body-equivalent ranges by subtracting typical wearing ease for the fit (`EaseGuidelines` — general guidance, not brand data, and the app says so);
  - it **refuses** to recommend when the chart lacks the category's key measurements or you lack them (it lists what's missing), and reports **outside chart range** instead of guessing;
  - when an adjacent size is close in score, within your measurement uncertainty, or favoured by a different measurement, **both sizes are shown with the reason**;
  - the result screen shows your value ± uncertainty beside each size range, highlights the measurements that drove the result, and lists low-confidence inputs.

## Privacy and safety

- Onboarding asks for explicit consent: an adult confirmation (required), an acknowledgement that results are estimates (required), and camera-use consent (optional, and can be withdrawn in Settings). iOS also asks for camera permission at first capture.
- **On-device only.** Vision runs locally. The app has no network code, so photos, video, depth and measurements are never uploaded.
- **Photos aren't stored.** Frames are deep-copied into memory for analysis and released when the flow closes. Saving one photo per view is an explicit opt-in (off by default), and saved photos can be deleted per session or all at once.
- Data files use `FileProtectionType.complete` and are **excluded from backups**.
- **Deletion:** delete a session, a session's photos, a profile (with its history and photos), all photos, or all data.
- **No sensitive inference.** Nothing infers age, health, ethnicity, identity or similar. Chart lines are chosen by the user.
- **Adults only.** Profiles can't be saved without confirming the person is 18+.
- `PrivacyInfo.xcprivacy` declares no tracking and no collected data. It also gives the required reason for UserDefaults (CA92.1).

## What still needs a trained model, device testing or verified data

| Item | Why | Needed |
|---|---|---|
| Calibration factors for every girth and length | The ellipse model and landmark offsets have systematic bias | Tape-measured study, then fit `CalibrationProfile` ([ACCURACY_TESTING.md](ACCURACY_TESTING.md)) |
| Neck, bicep, thigh, knee, calf | The outline alone is a weak signal | A trained body-shape model (for example, regression from silhouettes and keypoints to girths, or a parametric body-model fit) |
| Underbust, wrist, ankle, rise, front length | Not observable at full-body distance through clothing | A trained model plus close-up capture, or keep manual |
| Clothing-thickness compensation | Loose clothes inflate the outline | A trained model or garment segmentation |
| Live-check thresholds (distance, arm angle, light, steadiness) | Chosen from first principles | Tuning on physical devices with varied users and rooms |
| LiDAR scale offset (+8 cm surface-to-outline), depth-window placement | Assumes a centred torso | Device testing on Pro models |
| Vision 3D pose height cross-check | Behaviour with streamed LiDAR depth not yet observed | Device testing |
| Camera, rotation, depth-format selection, front-camera path | Hardware-dependent | Testing on several iPhone generations, including non-Pro models |
| Brand size charts | Only fictional demo data is bundled | Verified charts copied from official sources, with URL and date |
| App target compilation | Written without Xcode | Build in Xcode or via the included CI workflow, and fix any SDK-level issues |

## Apple documentation used

These were checked against Apple's documentation (availability as listed there):

- `VNDetectHumanBodyPoseRequest` (iOS 14): https://developer.apple.com/documentation/vision/vndetecthumanbodyposerequest
- `VNDetectHumanBodyPose3DRequest` (iOS 17): https://developer.apple.com/documentation/vision/vndetecthumanbodypose3drequest
- `VNHumanBodyPose3DObservation.bodyHeight` (iOS 17): https://developer.apple.com/documentation/vision/vnhumanbodypose3dobservation/bodyheight
- `VNGeneratePersonSegmentationRequest` (iOS 15): https://developer.apple.com/documentation/vision/vngeneratepersonsegmentationrequest
- `VNImageRequestHandler` (depth initialisers): https://developer.apple.com/documentation/vision/vnimagerequesthandler
- `AVCaptureDevice.DeviceType.builtInLiDARDepthCamera` (iOS 15.4): https://developer.apple.com/documentation/avfoundation/avcapturedevice/devicetype-swift.struct/builtinlidardepthcamera
- `AVCaptureDepthDataOutput` (iOS 11): https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput
- `AVCaptureDataOutputSynchronizer` (iOS 11): https://developer.apple.com/documentation/avfoundation/avcapturedataoutputsynchronizer
- `AVCameraCalibrationData.intrinsicMatrix` (iOS 11): https://developer.apple.com/documentation/avfoundation/avcameracalibrationdata/intrinsicmatrix
- `AVCaptureConnection.videoRotationAngle` (iOS 17): https://developer.apple.com/documentation/avfoundation/avcaptureconnection/videorotationangle
- `AVCaptureDevice.RotationCoordinator` (iOS 17): https://developer.apple.com/documentation/avfoundation/avcapturedevice/rotationcoordinator
- `ARBodyTrackingConfiguration` (iOS 13): https://developer.apple.com/documentation/arkit/arbodytrackingconfiguration
- `ARConfiguration.FrameSemantics.sceneDepth` (iOS 14): https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics-swift.struct/scenedepth
- `CMMotionManager`: https://developer.apple.com/documentation/coremotion/cmmotionmanager
- Privacy manifest: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
