import Foundation
import Observation
import MeasureMeCore

/// User preferences persisted in UserDefaults. Nothing here is sent anywhere.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }
    /// Explicit consent to use the camera for on-device measurement estimation. Can be withdrawn.
    var cameraConsentGiven: Bool { didSet { defaults.set(cameraConsentGiven, forKey: Keys.consent) } }
    var defaultUnit: LengthUnit { didSet { defaults.set(defaultUnit.rawValue, forKey: Keys.unit) } }
    var voiceGuidance: Bool { didSet { defaults.set(voiceGuidance, forKey: Keys.voice) } }
    /// Off by default: capture photos are discarded after analysis unless the user turns this on.
    var saveCapturePhotos: Bool { didSet { defaults.set(saveCapturePhotos, forKey: Keys.savePhotos) } }
    var showDemoCharts: Bool { didSet { defaults.set(showDemoCharts, forKey: Keys.demo) } }
    /// Use LiDAR depth as a scale cross-check when the device has it.
    var useDepthWhenAvailable: Bool { didSet { defaults.set(useDepthWhenAvailable, forKey: Keys.depth) } }

    private enum Keys {
        static let onboarding = "settings.hasCompletedOnboarding"
        static let consent = "settings.cameraConsentGiven"
        static let unit = "settings.defaultUnit"
        static let voice = "settings.voiceGuidance"
        static let savePhotos = "settings.saveCapturePhotos"
        static let demo = "settings.showDemoCharts"
        static let depth = "settings.useDepthWhenAvailable"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.voice: true, Keys.demo: true, Keys.depth: true])
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        cameraConsentGiven = defaults.bool(forKey: Keys.consent)
        let localeDefault: LengthUnit = Locale.current.measurementSystem == .us ? .inches : .centimetres
        defaultUnit = LengthUnit(rawValue: defaults.string(forKey: Keys.unit) ?? "") ?? localeDefault
        voiceGuidance = defaults.bool(forKey: Keys.voice)
        saveCapturePhotos = defaults.bool(forKey: Keys.savePhotos)
        showDemoCharts = defaults.bool(forKey: Keys.demo)
        useDepthWhenAvailable = defaults.bool(forKey: Keys.depth)
    }

    func resetAll() {
        for key in [Keys.onboarding, Keys.consent, Keys.unit, Keys.voice, Keys.savePhotos, Keys.demo, Keys.depth] {
            defaults.removeObject(forKey: key)
        }
        hasCompletedOnboarding = false
        cameraConsentGiven = false
        voiceGuidance = true
        saveCapturePhotos = false
        showDemoCharts = true
        useDepthWhenAvailable = true
    }
}
