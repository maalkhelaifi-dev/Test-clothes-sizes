import Foundation
import Observation
import MeasureMeCore

/// App-wide state: profiles, measurement history and the size-chart library.
/// All data is stored locally (see `LocalStore`). There is no network code in this app.
@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [PersonProfile] = []
    private(set) var userCharts: [SizeChart] = []
    private(set) var demoCharts: [SizeChart] = []
    var loadError: String?

    let settings: AppSettings
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored let photoStore: CapturePhotoStore

    private static let profilesFile = "profiles.json"
    private static let chartsFile = "user-size-charts.json"

    init(settings: AppSettings? = nil, store: LocalStore = LocalStore()) {
        self.settings = settings ?? AppSettings()
        self.store = store
        self.photoStore = CapturePhotoStore(store: store)
        load()
    }

    // MARK: Loading

    private func load() {
        do {
            demoCharts = try DemoSizeCharts.load()
        } catch {
            demoCharts = []
            loadError = "Demo size charts could not be loaded: \(error.localizedDescription)"
        }
        do {
            profiles = try store.load([PersonProfile].self, from: Self.profilesFile) ?? []
            userCharts = try store.load([SizeChart].self, from: Self.chartsFile) ?? []
        } catch {
            loadError = "Saved profiles or charts could not be read (\(error.localizedDescription)). Your data has not been changed."
        }
    }

    private func persistProfiles() throws { try store.save(profiles, to: Self.profilesFile) }
    private func persistCharts() throws { try store.save(userCharts, to: Self.chartsFile) }

    // MARK: Profiles

    func profile(id: UUID) -> PersonProfile? { profiles.first { $0.id == id } }

    func save(profile: PersonProfile) throws {
        try profile.validate()
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[i] = profile
        } else {
            profiles.append(profile)
        }
        try persistProfiles()
    }

    /// Deletes the profile, its whole measurement history and any saved capture photos.
    func deleteProfile(id: UUID) throws {
        if let p = profile(id: id) {
            for s in p.sessions { photoStore.delete(sessionID: s.id) }
        }
        profiles.removeAll { $0.id == id }
        try persistProfiles()
    }

    func addSession(_ session: MeasurementSession, to profileID: UUID) throws {
        guard var p = profile(id: profileID) else { return }
        p.sessions.append(session)
        try save(profile: p)
    }

    func updateSession(_ session: MeasurementSession, in profileID: UUID) throws {
        guard var p = profile(id: profileID), let i = p.sessions.firstIndex(where: { $0.id == session.id }) else { return }
        p.sessions[i] = session
        try save(profile: p)
    }

    func deleteSession(_ sessionID: UUID, from profileID: UUID) throws {
        guard var p = profile(id: profileID) else { return }
        photoStore.delete(sessionID: sessionID)
        p.sessions.removeAll { $0.id == sessionID }
        try save(profile: p)
    }

    /// Removes saved photos for one session but keeps its measurements.
    func deleteCapturePhotos(sessionID: UUID, profileID: UUID) throws {
        guard var p = profile(id: profileID), let i = p.sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        photoStore.delete(sessionID: sessionID)
        p.sessions[i].savedPhotoFiles = []
        try save(profile: p)
    }

    /// Removes every saved capture photo for every profile.
    func deleteAllCapturePhotos() throws {
        photoStore.deleteAll()
        for i in profiles.indices {
            for j in profiles[i].sessions.indices { profiles[i].sessions[j].savedPhotoFiles = [] }
        }
        try persistProfiles()
    }

    var savedPhotoCount: Int {
        profiles.reduce(0) { $0 + $1.sessions.reduce(0) { $0 + $1.savedPhotoFiles.count } }
    }

    // MARK: Size charts

    var chartLibrary: SizeChartLibrary {
        SizeChartLibrary(charts: userCharts + (settings.showDemoCharts ? demoCharts : []))
    }

    func isUserChart(_ id: UUID) -> Bool { userCharts.contains { $0.id == id } }

    /// Adds or updates a user chart. Non-demo charts must cite an official source and verification date.
    func saveChart(_ chart: SizeChart) throws {
        try SizeChartValidator.validate(chart, isUserChart: true)
        if let i = userCharts.firstIndex(where: { $0.id == chart.id }) {
            userCharts[i] = chart
        } else {
            userCharts.append(chart)
        }
        try persistCharts()
    }

    func deleteChart(id: UUID) throws {
        userCharts.removeAll { $0.id == id }
        try persistCharts()
    }

    /// Imports charts from a JSON file. Every imported chart is validated; nothing is saved if any fail.
    @discardableResult
    func importCharts(from data: Data) throws -> Int {
        let charts = try SizeChartFile.decodeCharts(from: data)
        for c in charts { try SizeChartValidator.validate(c, isUserChart: true) }
        for c in charts {
            if let i = userCharts.firstIndex(where: { $0.id == c.id }) { userCharts[i] = c } else { userCharts.append(c) }
        }
        try persistCharts()
        return charts.count
    }

    /// Writes the user's charts to a temporary JSON file for sharing.
    func exportUserCharts() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MeasureMe-size-charts.json")
        try SizeChartFile.encode(userCharts).write(to: url, options: .atomic)
        return url
    }

    // MARK: Delete everything

    func deleteAllData() throws {
        photoStore.deleteAll()
        try store.deleteEverything()
        profiles = []
        userCharts = []
        settings.resetAll()
    }
}
