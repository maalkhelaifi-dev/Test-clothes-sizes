import Foundation

/// A body measurement the app knows about.
///
/// These are *body* measurements (taken on the person), never garment measurements.
/// Garment charts are mapped to body measurements through `SizeChart.kind` and `EaseGuidelines`.
public enum MeasurementKind: String, Codable, CaseIterable, Identifiable, Sendable {
    // Core
    case height
    case neck
    case shoulderWidth
    case chest          // chest / bust (fullest part)
    case underbust
    case waist          // natural waist (narrowest part of torso)
    case hips           // hips / seat (fullest part)
    // Arms
    case sleeveLength   // centre back neck → over shoulder → wrist
    case armLength      // shoulder point → wrist
    case bicep
    case wrist
    // Legs
    case inseam         // crotch → floor (barefoot)
    case outseam        // natural waist → floor along the side
    case thigh
    case knee
    case calf
    case ankle
    // Category-specific extras
    case napeToWaist    // back length: nape of neck → natural waist (dresses, jackets)
    case shoulderToWaist // front: shoulder/neck point → waist (dresses)
    case rise           // seated crotch depth (trousers)

    public var id: String { rawValue }

    public enum Group: String, CaseIterable, Sendable {
        case core = "Body"
        case arms = "Arms"
        case legs = "Legs"
        case extra = "Category-specific"
    }

    public var group: Group {
        switch self {
        case .height, .neck, .shoulderWidth, .chest, .underbust, .waist, .hips: return .core
        case .sleeveLength, .armLength, .bicep, .wrist: return .arms
        case .inseam, .outseam, .thigh, .knee, .calf, .ankle: return .legs
        case .napeToWaist, .shoulderToWaist, .rise: return .extra
        }
    }

    public var displayName: String {
        switch self {
        case .height: return "Height"
        case .neck: return "Neck"
        case .shoulderWidth: return "Shoulder width"
        case .chest: return "Chest / bust"
        case .underbust: return "Underbust"
        case .waist: return "Waist"
        case .hips: return "Hips / seat"
        case .sleeveLength: return "Sleeve length"
        case .armLength: return "Arm length"
        case .bicep: return "Bicep"
        case .wrist: return "Wrist"
        case .inseam: return "Inseam"
        case .outseam: return "Outseam"
        case .thigh: return "Thigh"
        case .knee: return "Knee"
        case .calf: return "Calf"
        case .ankle: return "Ankle"
        case .napeToWaist: return "Back length (nape to waist)"
        case .shoulderToWaist: return "Front length (shoulder to waist)"
        case .rise: return "Rise (seated crotch depth)"
        }
    }

    /// True for girths measured around the body; false for straight lengths/widths.
    public var isCircumference: Bool {
        switch self {
        case .neck, .chest, .underbust, .waist, .hips, .bicep, .wrist, .thigh, .knee, .calf, .ankle:
            return true
        default:
            return false
        }
    }

    /// How to take the measurement with a tape measure. Shown next to manual entry.
    public var howToMeasure: String {
        switch self {
        case .height: return "Stand barefoot against a wall, heels together, looking straight ahead. Measure from the floor to the top of the head."
        case .neck: return "Measure around the base of the neck where a shirt collar sits, keeping one finger between tape and neck."
        case .shoulderWidth: return "Measure across the back from the tip of one shoulder bone to the other."
        case .chest: return "Measure around the fullest part of the chest/bust, under the arms, keeping the tape level."
        case .underbust: return "Measure around the ribcage directly below the bust, keeping the tape level and snug."
        case .waist: return "Measure around the natural waist — usually the narrowest part of the torso, above the belly button. Breathe out normally."
        case .hips: return "Stand with feet together and measure around the fullest part of the hips and seat."
        case .sleeveLength: return "With the arm relaxed, measure from the centre back of the neck, over the shoulder, down to the wrist bone."
        case .armLength: return "Measure from the shoulder bone tip, down the outside of a slightly bent arm, to the wrist bone."
        case .bicep: return "Measure around the fullest part of the relaxed upper arm."
        case .wrist: return "Measure around the wrist just above the wrist bone."
        case .inseam: return "Standing barefoot, measure from the crotch straight down the inner leg to the floor."
        case .outseam: return "Measure from the natural waist down the outside of the leg to the floor."
        case .thigh: return "Measure around the fullest part of the upper thigh, just below the crotch."
        case .knee: return "Measure around the knee with the leg straight."
        case .calf: return "Measure around the fullest part of the calf."
        case .ankle: return "Measure around the narrowest part of the leg just above the ankle bone."
        case .napeToWaist: return "Measure from the prominent bone at the back of the neck straight down to the natural waist."
        case .shoulderToWaist: return "Measure from where the shoulder meets the neck, over the bust, down to the natural waist."
        case .rise: return "Sit upright on a flat chair. Measure along the side from the natural waist down to the chair seat."
        }
    }

    /// Plausible range for an adult, in centimetres. Values outside this range are rejected
    /// by validation (they almost certainly indicate a unit or entry mistake).
    public var plausibleRangeCM: ClosedRange<Double> {
        switch self {
        case .height: return 130...230
        case .neck: return 25...60
        case .shoulderWidth: return 28...65
        case .chest: return 65...180
        case .underbust: return 55...160
        case .waist: return 50...180
        case .hips: return 65...190
        case .sleeveLength: return 60...105
        case .armLength: return 40...85
        case .bicep: return 18...60
        case .wrist: return 12...25
        case .inseam: return 55...105
        case .outseam: return 75...135
        case .thigh: return 35...95
        case .knee: return 26...60
        case .calf: return 24...60
        case .ankle: return 16...35
        case .napeToWaist: return 32...60
        case .shoulderToWaist: return 32...65
        case .rise: return 18...40
        }
    }

    /// What the camera pipeline can do for this measurement.
    public var cameraSupport: CameraSupport {
        switch self {
        case .height: return .userProvided
        case .shoulderWidth, .armLength, .sleeveLength, .inseam, .outseam, .napeToWaist:
            return .estimatedFromLandmarks
        case .chest, .waist, .hips:
            return .estimatedFromSilhouette
        case .neck, .bicep, .thigh, .knee, .calf:
            return .lowConfidenceSilhouette
        case .underbust, .wrist, .ankle, .shoulderToWaist, .rise:
            return .manualOnly
        }
    }

    public enum CameraSupport: String, Sendable {
        /// Height is the scale reference and is always entered by the user.
        case userProvided
        /// Straight-line lengths derived from pose landmarks and scaled by height.
        case estimatedFromLandmarks
        /// Girths estimated from front width + side depth silhouettes (needs front AND side views).
        case estimatedFromSilhouette
        /// Girths of small or occluded body parts; estimated but always low confidence.
        case lowConfidenceSilhouette
        /// Not reliably observable through clothing or at full-body distance — enter by hand.
        case manualOnly

        public var explanation: String {
            switch self {
            case .userProvided: return "Entered by you; used as the scale reference."
            case .estimatedFromLandmarks: return "Estimated from body landmarks scaled by your height."
            case .estimatedFromSilhouette: return "Estimated from front and side outlines. Needs both views."
            case .lowConfidenceSilhouette: return "Rough estimate from the outline; please check with a tape measure."
            case .manualOnly: return "Cannot be estimated reliably from the camera. Please measure by hand."
            }
        }
    }
}
