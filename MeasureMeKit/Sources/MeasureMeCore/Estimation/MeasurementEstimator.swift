import Foundation

/// Correction factors applied to raw geometric estimates.
///
/// Defaults are UNCALIBRATED first guesses (1.0 except where a known systematic bias exists).
/// They should be fitted against tape-measure data from a test group — see ACCURACY_TESTING.md.
public struct CalibrationProfile: Codable, Equatable, Sendable {
    public var factors: [MeasurementKind: Double]
    public var name: String

    public init(name: String, factors: [MeasurementKind: Double]) {
        self.name = name
        self.factors = factors
    }

    /// Vision shoulder joints sit near the centre of the shoulder joint, inside the bony shoulder tip
    /// a tape measure uses, so the joint distance is scaled up. All other factors are 1.0 until calibrated.
    public static let uncalibrated = CalibrationProfile(name: "Uncalibrated defaults", factors: [.shoulderWidth: 1.18])

    public func factor(_ kind: MeasurementKind) -> Double { factors[kind] ?? 1.0 }
}

/// One estimated measurement, or the reason it is unavailable.
public struct MeasurementEstimate: Equatable, Identifiable, Sendable {
    public var id: MeasurementKind { kind }
    public let kind: MeasurementKind
    public let valueCM: Double?
    public let confidence: ConfidenceLevel
    public let uncertaintyCM: Double
    public let method: String
    public let unavailableReason: String?

    public init(kind: MeasurementKind, valueCM: Double?, confidence: ConfidenceLevel, uncertaintyCM: Double,
                method: String, unavailableReason: String?) {
        self.kind = kind
        self.valueCM = valueCM
        self.confidence = confidence
        self.uncertaintyCM = uncertaintyCM
        self.method = method
        self.unavailableReason = unavailableReason
    }

    public var isAvailable: Bool { valueCM != nil }

    public static func unavailable(_ kind: MeasurementKind, _ reason: String) -> MeasurementEstimate {
        MeasurementEstimate(kind: kind, valueCM: nil, confidence: .low, uncertaintyCM: 0, method: "", unavailableReason: reason)
    }
}

public struct EstimationResult: Equatable, Sendable {
    public var estimates: [MeasurementKind: MeasurementEstimate]
    public var warnings: [String]
    public var framesUsed: Int

    public init(estimates: [MeasurementKind: MeasurementEstimate], warnings: [String], framesUsed: Int) {
        self.estimates = estimates
        self.warnings = warnings
        self.framesUsed = framesUsed
    }

    /// Available estimates as stored measurement values (source = camera estimate).
    public func measurementSet(capturedAt date: Date = Date()) -> MeasurementSet {
        MeasurementSet(estimates.values.compactMap { e in
            guard let v = e.valueCM else { return nil }
            return MeasurementValue(kind: e.kind, valueCM: v, source: .cameraEstimate, confidence: e.confidence,
                                    uncertaintyCM: e.uncertaintyCM, capturedAt: date, method: e.method)
        })
    }

    public var sorted: [MeasurementEstimate] {
        MeasurementKind.allCases.compactMap { estimates[$0] }
    }
}

/// Converts analysed views (pose landmarks + person silhouette) into body measurement estimates.
///
/// Method summary:
/// * **Scale**: the user's height divided by the silhouette's vertical extent gives cm per pixel at the body.
///   LiDAR depth and Vision 3D body height, when present, are used only as cross-checks.
/// * **Lengths** (shoulder, arm, sleeve, inseam, outseam): pose landmark distances × scale.
/// * **Torso girths** (chest, waist, hips): front silhouette width and side silhouette depth at the same
///   relative height, combined as an ellipse perimeter. Requires both front and side views.
/// * **Limb/neck girths**: rough ellipse/circle estimates, always low confidence.
/// * Everything else is reported as unavailable — never guessed.
public enum MeasurementEstimator {

    struct Raw {
        var value: Double
        var confidence: ConfidenceLevel
        var uncertainty: Double
        var method: String
    }

    struct FrameResult {
        var values: [MeasurementKind: Raw] = [:]
        var unavailable: [MeasurementKind: String] = [:]
        var warnings: [String] = []
    }

    /// Scale and extent of the person in one view's mask.
    struct Geometry {
        let mask: SilhouetteMask
        let top: Int
        let bottom: Int
        var heightRows: Double { Double(bottom - top + 1) }
        let cmPerRow: Double
        let cmPerCol: Double
        let cmPerImagePixel: Double
        let touchesTop: Bool
        let touchesBottom: Bool

        init?(obs: ViewObservation, heightCM: Double) {
            guard let mask = obs.mask, let ext = mask.verticalExtent() else { return nil }
            self.mask = mask
            top = ext.top
            bottom = ext.bottom
            let rows = Double(ext.bottom - ext.top + 1)
            guard rows > Double(mask.height) * 0.2 else { return nil }
            cmPerRow = heightCM / rows
            let imagePixelsPerRow = Double(obs.imageHeight) / Double(mask.height)
            cmPerImagePixel = cmPerRow / imagePixelsPerRow
            cmPerCol = cmPerImagePixel * Double(obs.imageWidth) / Double(mask.width)
            touchesTop = ext.top <= 1
            touchesBottom = ext.bottom >= mask.height - 2
        }

        func row(_ p: NormalizedPoint) -> Int { Int((p.y * Double(mask.height)).rounded()) }
        func col(_ p: NormalizedPoint) -> Int { Int((p.x * Double(mask.width)).rounded()) }
        /// Height above the floor as a fraction of stature for a mask row.
        func fraction(row: Int) -> Double { Double(bottom - row) / heightRows }
        func row(fraction: Double) -> Int { Int((Double(bottom) - fraction * heightRows).rounded()) }
    }

    // MARK: Public API

    public static func estimate(
        heightCM: Double,
        fronts: [ViewObservation],
        sides: [ViewObservation] = [],
        backs: [ViewObservation] = [],
        requested: [MeasurementKind] = MeasurementKind.allCases,
        calibration: CalibrationProfile = .uncalibrated
    ) -> EstimationResult {
        var estimates: [MeasurementKind: MeasurementEstimate] = [:]
        var warnings: [String] = []

        guard !fronts.isEmpty else {
            for kind in requested where kind != .height {
                estimates[kind] = .unavailable(kind, "No usable front view was captured.")
            }
            return EstimationResult(estimates: estimates, warnings: ["No usable front view was captured."], framesUsed: 0)
        }

        var frames: [FrameResult] = []
        for (i, front) in fronts.enumerated() {
            let side = sides.isEmpty ? nil : sides[i % sides.count]
            let back = backs.isEmpty ? nil : backs[i % backs.count]
            frames.append(estimateFrame(heightCM: heightCM, front: front, side: side, back: back, calibration: calibration))
        }
        for f in frames {
            for w in f.warnings where !warnings.contains(w) { warnings.append(w) }
        }

        for kind in requested {
            if kind == .height { continue }
            let samples = frames.compactMap { $0.values[kind] }
            guard !samples.isEmpty else {
                let reason = frames.compactMap { $0.unavailable[kind] }.first
                    ?? kind.cameraSupport.explanation
                estimates[kind] = .unavailable(kind, reason)
                continue
            }
            let values = samples.map(\.value).sorted()
            let median = values.count % 2 == 1
                ? values[values.count / 2]
                : (values[values.count / 2 - 1] + values[values.count / 2]) / 2
            let spread = (values.last! - values.first!) / 2
            var confidence = samples.map(\.confidence).min()!
            // A large frame-to-frame spread means the estimate is unstable.
            if samples.count > 1, spread > max(2.0, median * 0.04) { confidence = confidence.lowered() }
            let base = samples.map(\.uncertainty).reduce(0, +) / Double(samples.count)
            let uncertainty = max(base, spread)
            let range = kind.plausibleRangeCM
            if !range.contains(median) {
                estimates[kind] = .unavailable(kind, "The estimate was outside the expected adult range, so it was discarded. Please measure by hand or retake the photos.")
                continue
            }
            estimates[kind] = MeasurementEstimate(kind: kind, valueCM: median, confidence: confidence,
                                                  uncertaintyCM: uncertainty, method: samples[0].method, unavailableReason: nil)
        }
        return EstimationResult(estimates: estimates, warnings: warnings, framesUsed: frames.count)
    }

    // MARK: Geometry helpers

    public static func ellipsePerimeter(width: Double, depth: Double) -> Double {
        let a = width / 2, b = depth / 2
        guard a + b > 0 else { return 0 }
        let h = pow(a - b, 2) / pow(a + b, 2)
        return Double.pi * (a + b) * (1 + 3 * h / (10 + (4 - 3 * h).squareRoot()))
    }

    static func midpoint(_ a: NormalizedPoint?, _ b: NormalizedPoint?) -> NormalizedPoint? {
        switch (a, b) {
        case let (a?, b?): return NormalizedPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }

    /// x position (mask columns) of a limb polyline at a given row, or nil when the row is outside the limb.
    static func limbX(atRow y: Int, points: [(Int, Int)]) -> Int? {
        guard points.count >= 2 else { return nil }
        for i in 1..<points.count {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            let lo = min(y0, y1), hi = max(y0, y1)
            guard y >= lo, y <= hi else { continue }
            if y1 == y0 { return (x0 + x1) / 2 }
            let t = Double(y - y0) / Double(y1 - y0)
            return Int((Double(x0) + t * Double(x1 - x0)).rounded())
        }
        return nil
    }

    // MARK: Per-frame estimation

    static func estimateFrame(heightCM: Double, front: ViewObservation, side: ViewObservation?, back: ViewObservation?,
                              calibration: CalibrationProfile) -> FrameResult {
        var r = FrameResult()
        let W = Double(front.imageWidth), H = Double(front.imageHeight)
        func px(_ a: NormalizedPoint, _ b: NormalizedPoint) -> Double { hypot((a.x - b.x) * W, (a.y - b.y) * H) }

        let qualityPenalty = front.frameQuality < 0.6 ? 1 : 0
        let g = Geometry(obs: front, heightCM: heightCM)
        let sideG = side.flatMap { Geometry(obs: $0, heightCM: heightCM) }
        let backG = back.flatMap { Geometry(obs: $0, heightCM: heightCM) }

        // --- Scale -------------------------------------------------------------------------------
        var cmPerImagePx: Double
        var scaleConfidence: ConfidenceLevel = .high
        if let g {
            cmPerImagePx = g.cmPerImagePixel
            if g.touchesTop || g.touchesBottom {
                r.warnings.append("Your head or feet touched the edge of the frame, so the height-based scale may be off. Step back and retake.")
                scaleConfidence = .low
            }
        } else if let nose = front.joint(.nose),
                  let ankle = midpoint(front.joint(.leftAnkle), front.joint(.rightAnkle)) {
            // Fallback without a silhouette: nose-to-ankle is roughly 87% of stature in adults.
            cmPerImagePx = 0.875 * heightCM / max(1, px(nose, ankle))
            scaleConfidence = .low
            r.warnings.append("The body outline could not be separated from the background, so only rough lengths were estimated.")
        } else {
            for kind in MeasurementKind.allCases where kind != .height {
                r.unavailable[kind] = "The full body was not detected in the front view."
            }
            r.warnings.append("The full body was not detected in the front view. Retake with your whole body in the frame.")
            return r
        }

        if let depthScale = front.depthCMPerImagePixel, depthScale > 0 {
            let ratio = cmPerImagePx / depthScale
            if abs(ratio - 1) > 0.08 {
                r.warnings.append(String(format: "The LiDAR depth reading disagrees with your entered height by %.0f%%. Check your height, or retake standing on the same level as the camera.", abs(ratio - 1) * 100))
                scaleConfidence = min(scaleConfidence, .medium)
            }
        }
        if let h3d = front.pose3DBodyHeightCM, front.pose3DHeightIsMeasured, abs(h3d - heightCM) / heightCM > 0.06 {
            r.warnings.append(String(format: "The camera’s 3D estimate of your height (%.0f cm) differs from the height you entered (%.0f cm). Your entered height is used as the scale.", h3d, heightCM))
            scaleConfidence = min(scaleConfidence, .medium)
        }

        func cap(_ c: ConfidenceLevel) -> ConfidenceLevel {
            min(c, scaleConfidence).lowered(by: qualityPenalty)
        }
        func put(_ kind: MeasurementKind, _ value: Double, _ c: ConfidenceLevel, _ unc: Double, _ method: String) {
            let v = value * calibration.factor(kind)
            let conf = cap(c)
            let extra = conf == .low ? 1.6 : 1.0
            r.values[kind] = Raw(value: v, confidence: conf, uncertainty: unc * extra, method: method)
        }

        // --- Manual-only measurements ----------------------------------------------------------
        for kind in MeasurementKind.allCases where kind.cameraSupport == .manualOnly {
            r.unavailable[kind] = kind.cameraSupport.explanation
        }

        // --- Landmark lengths ------------------------------------------------------------------
        let ls = front.joint(.leftShoulder), rs = front.joint(.rightShoulder)
        let le = front.joint(.leftElbow), re = front.joint(.rightElbow)
        let lw = front.joint(.leftWrist), rw = front.joint(.rightWrist)
        let lh = front.joint(.leftHip), rh = front.joint(.rightHip)
        let lk = front.joint(.leftKnee), rk = front.joint(.rightKnee)
        let la = front.joint(.leftAnkle), ra = front.joint(.rightAnkle)

        var shoulderWidth: Double?
        if let ls, let rs {
            let w = px(ls, rs) * cmPerImagePx
            shoulderWidth = w * calibration.factor(.shoulderWidth)
            put(.shoulderWidth, w, .medium, 2.5, "Distance between shoulder landmarks in the front view, scaled by your height.")
        } else {
            r.unavailable[.shoulderWidth] = "Both shoulders were not clearly visible in the front view."
        }

        var armLengths: [Double] = []
        if let ls, let le, let lw { armLengths.append((px(ls, le) + px(le, lw)) * cmPerImagePx) }
        if let rs, let re, let rw { armLengths.append((px(rs, re) + px(re, rw)) * cmPerImagePx) }
        if !armLengths.isEmpty {
            let arm = armLengths.reduce(0, +) / Double(armLengths.count)
            let agree = armLengths.count == 2 && abs(armLengths[0] - armLengths[1]) / arm < 0.04
            put(.armLength, arm, agree ? .high : .medium, agree ? 2.0 : 3.0, "Shoulder → elbow → wrist landmarks in the front view.")
            if let sw = shoulderWidth {
                let armCalibrated = arm * calibration.factor(.armLength)
                let sleeve = sw / 2 + armCalibrated
                // `put` applies the sleeve factor on top of its components' factors.
                put(.sleeveLength, sleeve, .medium, 3.0, "Half your shoulder width plus arm length.")
            } else {
                r.unavailable[.sleeveLength] = "Needs shoulder width, which was not detected."
            }
        } else {
            r.unavailable[.armLength] = "Shoulder, elbow and wrist were not all visible on either arm."
            r.unavailable[.sleeveLength] = "Shoulder, elbow and wrist were not all visible on either arm."
        }

        guard let g else {
            for kind in [MeasurementKind.chest, .waist, .hips, .neck, .bicep, .thigh, .knee, .calf, .inseam, .outseam, .napeToWaist] {
                r.unavailable[kind] = "Needs a clear body outline, which could not be separated from the background."
            }
            return r
        }

        // --- Torso levels from landmarks --------------------------------------------------------
        guard let shoulderMid = midpoint(ls, rs), let hipMid = midpoint(lh, rh) else {
            for kind in [MeasurementKind.chest, .waist, .hips, .thigh, .knee, .calf, .inseam, .outseam, .napeToWaist, .neck, .bicep] {
                r.unavailable[kind] = "Shoulders and hips were not both detected in the front view."
            }
            return r
        }
        let shoulderRow = g.row(shoulderMid), hipRow = g.row(hipMid)
        let span = Double(hipRow - shoulderRow)
        guard span > g.heightRows * 0.15 else {
            r.warnings.append("The body landmarks in the front view look inconsistent. Retake facing the camera.")
            return r
        }
        let shoulderX = Double(g.col(shoulderMid)), hipX = Double(g.col(hipMid))
        func centerX(row y: Int) -> Int {
            let t = min(1, max(0, Double(y - shoulderRow) / span))
            return Int((shoulderX + t * (hipX - shoulderX)).rounded())
        }
        let arms: [[(Int, Int)]] = [[ls, le, lw], [rs, re, rw]].map { pts in
            pts.compactMap { $0 }.map { (g.col($0), g.row($0)) }
        }
        func touchesArm(_ run: Range<Int>, row y: Int) -> Bool {
            for arm in arms {
                // Ignore the shoulder joint region itself; check the limb below it.
                if let x = limbX(atRow: y, points: arm), let first = arm.first, y > first.1 + Int(span * 0.1), run.contains(x) {
                    return true
                }
            }
            return false
        }

        struct Level { let row: Int; let widthCM: Double; let merged: Bool }
        func torsoLevel(from a: Double, to b: Double, widest: Bool) -> Level? {
            var best: Level?
            let start = shoulderRow + Int(a * span), end = shoulderRow + Int(b * span)
            guard start < end else { return nil }
            for y in start...end {
                guard let (w, run) = g.mask.medianWidth(row: y, containing: centerX(row: y)) else { continue }
                let level = Level(row: y, widthCM: w * g.cmPerCol, merged: touchesArm(run, row: y))
                if best == nil || (widest ? level.widthCM > best!.widthCM : level.widthCM < best!.widthCM) {
                    best = level
                }
            }
            return best
        }

        // Crotch (needed for hips band limit, inseam, thigh).
        let kneeRow = midpoint(lk, rk).map { g.row($0) } ?? (hipRow + Int(span * 1.0))
        let crotchRow = g.mask.crotchRow(centerX: Int(hipX), fromRow: hipRow, toRow: kneeRow)
        let hipBandEnd: Double = crotchRow.map { min(1.35, Double($0 - shoulderRow) / span - 0.02) } ?? 1.3

        let chest = torsoLevel(from: 0.22, to: 0.45, widest: true)
        let waist = torsoLevel(from: 0.55, to: 0.85, widest: false)
        let hips = torsoLevel(from: 0.92, to: max(0.95, hipBandEnd), widest: true)

        func sideDepthCM(atFraction f: Double) -> Double? {
            guard let sg = sideG else { return nil }
            return sg.mask.medianWidestWidth(row: sg.row(fraction: f)).map { $0 * sg.cmPerCol }
        }
        func backWidthCM(atFraction f: Double) -> Double? {
            guard let bg = backG else { return nil }
            let y = bg.row(fraction: f)
            let cx = midpoint(back?.joint(.leftHip), back?.joint(.rightHip)).map { bg.col($0) } ?? bg.mask.width / 2
            return bg.mask.medianWidth(row: y, containing: cx).map { $0.width * bg.cmPerCol }
        }

        func torsoGirth(_ kind: MeasurementKind, _ level: Level?) {
            guard let level else {
                r.unavailable[kind] = "The \(kind.displayName.lowercased()) level could not be found in the front outline."
                return
            }
            let f = g.fraction(row: level.row)
            guard let depth = sideDepthCM(atFraction: f) else {
                r.unavailable[kind] = side == nil
                    ? "Needs a side-view photo to estimate depth. One front photo cannot measure a girth."
                    : "The side-view outline was not clear at this height."
                return
            }
            var width = level.widthCM
            var conf: ConfidenceLevel = .medium
            var method = "Ellipse from front width and side depth."
            if let bw = backWidthCM(atFraction: f) {
                if abs(bw - width) / width > 0.08 {
                    r.warnings.append("Front and back outlines disagree at the \(kind.displayName.lowercased()) — loose clothing or a change in posture may be affecting the result.")
                    conf = .low
                }
                width = (width + bw) / 2
                method = "Ellipse from front/back width and side depth."
            }
            if level.merged {
                conf = .low
                r.warnings.append("Your arms seemed to touch your body at the \(kind.displayName.lowercased()) level, which makes it look wider. Hold your arms slightly further out and retake.")
            }
            if depth > width * 1.15 {
                conf = .low
                r.warnings.append("The side view looks wider than the front view. Make sure the side photo is taken exactly side-on.")
            }
            put(kind, ellipsePerimeter(width: width, depth: depth), conf, 4.0, method)
        }
        torsoGirth(.chest, chest)
        torsoGirth(.waist, waist)
        torsoGirth(.hips, hips)

        // --- Vertical lengths from the silhouette ----------------------------------------------
        if let crotchRow {
            let inseam = Double(g.bottom - crotchRow) * g.cmPerRow
            put(.inseam, inseam, .medium, 2.5, "Crotch gap to floor in the front outline, scaled by your height.")
        } else {
            r.unavailable[.inseam] = "The gap between the legs was not visible. Stand with feet hip-width apart in fitted trousers or shorts."
        }
        if let waist {
            put(.outseam, Double(g.bottom - waist.row) * g.cmPerRow, .medium, 3.0, "Natural waist level to floor, scaled by your height.")
            if let neck = front.joint(.neck) {
                // Vision's neck point sits between the shoulders, slightly below the nape bone.
                put(.napeToWaist, Double(waist.row - g.row(neck)) * g.cmPerRow, .low, 3.0, "Neck landmark to natural waist level (front view approximation).")
            } else {
                r.unavailable[.napeToWaist] = "The neck landmark was not detected."
            }
        } else {
            r.unavailable[.outseam] = "The waist level could not be found."
            r.unavailable[.napeToWaist] = "The waist level could not be found."
        }

        // --- Rough girths (always low confidence) ----------------------------------------------
        func limbGirth(_ kind: MeasurementKind, row y: Int, x: Int, angleFromVertical: Double = 0) {
            guard let (w, _) = g.mask.medianWidth(row: y, containing: x) else {
                r.unavailable[kind] = "The \(kind.displayName.lowercased()) outline was not clear."
                return
            }
            let width = w * g.cmPerCol * cos(angleFromVertical)
            let girth: Double
            let method: String
            if kind != .bicep, let depth = sideDepthCM(atFraction: g.fraction(row: y)), depth < width * 2.2 {
                // Side view shows both legs overlapping, which approximates one leg's depth.
                girth = ellipsePerimeter(width: width, depth: depth)
                method = "Rough ellipse from front width and side depth."
            } else {
                girth = Double.pi * width
                method = "Rough circle from front width."
            }
            put(kind, girth, .low, 3.0, method)
        }

        if let neck = front.joint(.neck), let nose = front.joint(.nose) {
            let neckRow = g.row(neck)
            let y = neckRow - Int(Double(neckRow - g.row(nose)) * 0.35)
            if let (w, _) = g.mask.medianWidth(row: y, containing: g.col(neck)) {
                let width = w * g.cmPerCol
                let depth = sideDepthCM(atFraction: g.fraction(row: y)) ?? width
                put(.neck, ellipsePerimeter(width: width, depth: min(depth, width * 1.2)), .low, 3.0, "Rough ellipse at the base of the neck. Hair and collars affect this.")
            } else {
                r.unavailable[.neck] = "The neck outline was not clear."
            }
        } else {
            r.unavailable[.neck] = "The neck and head landmarks were not detected."
        }

        let upperArms = [(ls, le), (rs, re)].compactMap { pair -> (NormalizedPoint, NormalizedPoint)? in
            guard let s = pair.0, let e = pair.1 else { return nil }
            return (s, e)
        }
        if let (s, e) = upperArms.first {
            let mid = NormalizedPoint(x: (s.x + e.x) / 2, y: (s.y + e.y) / 2)
            let angle = atan2(abs(e.x - s.x) * W, abs(e.y - s.y) * H)
            limbGirth(.bicep, row: g.row(mid), x: g.col(mid), angleFromVertical: angle)
        } else {
            r.unavailable[.bicep] = "The upper arm was not detected."
        }

        let hipJoint = lh ?? rh
        if let crotchRow, let hj = hipJoint {
            limbGirth(.thigh, row: crotchRow + Int(g.heightRows * 0.03), x: g.col(hj))
        } else {
            r.unavailable[.thigh] = "The gap between the legs was not visible."
        }
        if let k = lk ?? rk {
            limbGirth(.knee, row: g.row(k), x: g.col(k))
            if let a = (lk != nil ? la : ra) ?? la ?? ra {
                // Calf: widest part in the upper half of the lower leg.
                let kr = g.row(k), ar = g.row(a)
                var bestRow = kr, bestWidth = 0.0
                if ar - kr > 8 {
                    for y in (kr + (ar - kr) / 6)...(kr + (ar - kr) / 2) {
                        let x = Int(Double(g.col(k)) + Double(y - kr) / Double(ar - kr) * Double(g.col(a) - g.col(k)))
                        if let (w, _) = g.mask.medianWidth(row: y, containing: x), w > bestWidth {
                            bestWidth = w
                            bestRow = y
                        }
                    }
                }
                if bestWidth > 0 {
                    let x = Int(Double(g.col(k)) + Double(bestRow - kr) / Double(max(1, ar - kr)) * Double(g.col(a) - g.col(k)))
                    limbGirth(.calf, row: bestRow, x: x)
                } else {
                    r.unavailable[.calf] = "The lower leg outline was not clear."
                }
            } else {
                r.unavailable[.calf] = "The ankle was not detected."
            }
        } else {
            r.unavailable[.knee] = "The knees were not detected."
            r.unavailable[.calf] = "The knees were not detected."
        }

        return r
    }
}
