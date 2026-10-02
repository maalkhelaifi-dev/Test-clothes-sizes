import Foundation

/// How a measurement session was produced.
public enum SessionMethod: String, Codable, Sendable {
    case camera
    case manual
    case mixed

    public var displayName: String {
        switch self {
        case .camera: return "Camera"
        case .manual: return "Manual"
        case .mixed: return "Camera + manual"
        }
    }
}

/// Short, non-identifying summary of a camera capture (no images).
public struct CaptureSummary: Codable, Equatable, Sendable {
    public var viewsCaptured: [String]
    public var usedDepth: Bool
    public var lensDescription: String
    public var overallQuality: Double   // 0...1
    public var notes: [String]

    public init(viewsCaptured: [String], usedDepth: Bool, lensDescription: String, overallQuality: Double, notes: [String]) {
        self.viewsCaptured = viewsCaptured
        self.usedDepth = usedDepth
        self.lensDescription = lensDescription
        self.overallQuality = overallQuality
        self.notes = notes
    }
}

/// One saved set of measurements (a point in the measurement history).
public struct MeasurementSession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var category: ClothingCategory?
    public var method: SessionMethod
    public var measurements: MeasurementSet
    public var captureSummary: CaptureSummary?
    /// Relative file names of saved capture photos. Empty unless the user opted in to saving photos.
    public var savedPhotoFiles: [String]

    public init(id: UUID = UUID(), date: Date = Date(), category: ClothingCategory? = nil,
                method: SessionMethod, measurements: MeasurementSet,
                captureSummary: CaptureSummary? = nil, savedPhotoFiles: [String] = []) {
        self.id = id
        self.date = date
        self.category = category
        self.method = method
        self.measurements = measurements
        self.captureSummary = captureSummary
        self.savedPhotoFiles = savedPhotoFiles
    }

    /// Works out the method from the sources of the stored values.
    public static func inferMethod(for set: MeasurementSet) -> SessionMethod {
        let sources = Set(set.sorted.filter { $0.kind != .height }.map(\.source))
        if sources.isEmpty || sources == [.manual] { return .manual }
        if sources.contains(.manual) || sources.contains(.cameraEdited) { return .mixed }
        return .camera
    }
}

/// A person whose measurements are stored. Profiles hold no photos and no inferred attributes —
/// only what the user typed or chose and the measurement history.
public struct PersonProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Free-text label chosen by the user (e.g. "Me", "Alex"). Not used for anything else.
    public var displayName: String
    public var heightCM: Double
    public var preferredUnit: LengthUnit
    public var defaultFit: FitPreference
    /// Chart lines the user wants to see (e.g. unisex, womenswear, menswear). Chosen by the user, never inferred.
    public var preferredAudiences: [SizeAudience]
    /// The user confirmed this profile is for an adult (18+). Required to create a profile in this MVP.
    public var adultConfirmed: Bool
    public var createdAt: Date
    public var sessions: [MeasurementSession]

    public init(id: UUID = UUID(), displayName: String, heightCM: Double, preferredUnit: LengthUnit = .centimetres,
                defaultFit: FitPreference = .regular, preferredAudiences: [SizeAudience] = [.unisex],
                adultConfirmed: Bool, createdAt: Date = Date(), sessions: [MeasurementSession] = []) {
        self.id = id
        self.displayName = displayName
        self.heightCM = heightCM
        self.preferredUnit = preferredUnit
        self.defaultFit = defaultFit
        self.preferredAudiences = preferredAudiences
        self.adultConfirmed = adultConfirmed
        self.createdAt = createdAt
        self.sessions = sessions
    }

    /// Sessions newest first.
    public var history: [MeasurementSession] {
        sessions.sorted { $0.date > $1.date }
    }

    /// The most recent value for every measurement across all sessions, with height from the profile.
    public var latestMeasurements: MeasurementSet {
        var result = MeasurementSet()
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            result = result.merging(session.measurements)
        }
        result[.height] = MeasurementValue.manual(.height, cm: heightCM, at: createdAt)
        return result
    }

    public enum ProfileError: Error, Equatable, LocalizedError {
        case adultConfirmationRequired
        case emptyName
        case invalidHeight(String)

        public var errorDescription: String? {
            switch self {
            case .adultConfirmationRequired:
                return "Measure Me is for adults only. Please confirm this profile is for someone aged 18 or over."
            case .emptyName:
                return "Please enter a name or nickname for this profile."
            case .invalidHeight(let message):
                return message
            }
        }
    }

    /// Checks the profile can be saved.
    public func validate() throws {
        guard adultConfirmed else { throw ProfileError.adultConfirmationRequired }
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ProfileError.emptyName }
        if let issue = MeasurementValidator.validate(.height, cm: heightCM).first {
            throw ProfileError.invalidHeight(issue.message)
        }
    }
}
