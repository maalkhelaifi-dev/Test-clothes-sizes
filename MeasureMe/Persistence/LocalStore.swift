import Foundation

/// Stores JSON documents in the app's Application Support directory.
///
/// Files are written with `.completeFileProtection` (encrypted while the device is locked)
/// and the directory is excluded from iCloud/iTunes backups, so measurement data stays on this device.
struct LocalStore {
    let directory: URL

    init(directoryName: String = "MeasureMe") {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(directoryName, isDirectory: true)
    }

    init(directory: URL) {
        self.directory = directory
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func load<T: Decodable>(_ type: T.Type, from name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.makeDecoder().decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to name: String) throws {
        try prepare()
        let data = try Self.makeEncoder().encode(value)
        try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
    }

    func deleteEverything() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

/// Optional on-device storage for capture photos. Only used when the user turns on "Save capture photos".
struct CapturePhotoStore {
    let directory: URL

    init(store: LocalStore) {
        directory = store.directory.appendingPathComponent("Captures", isDirectory: true)
    }

    private func folder(for sessionID: UUID) -> URL {
        directory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
    }

    /// Saves a JPEG and returns its file name relative to the session folder.
    func save(jpeg: Data, sessionID: UUID, name: String) throws -> String {
        let dir = folder(for: sessionID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        let fileName = "\(name).jpg"
        try jpeg.write(to: dir.appendingPathComponent(fileName), options: [.atomic, .completeFileProtection])
        return fileName
    }

    func url(sessionID: UUID, fileName: String) -> URL {
        folder(for: sessionID).appendingPathComponent(fileName)
    }

    func delete(sessionID: UUID) {
        try? FileManager.default.removeItem(at: folder(for: sessionID))
    }

    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
