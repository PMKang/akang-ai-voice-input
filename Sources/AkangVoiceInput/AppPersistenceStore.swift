import Foundation

struct AppDataSnapshot: Codable, Equatable {
    var history: [HistoryItem]
    var dictionary: [DictionaryEntry]

    static let empty = AppDataSnapshot(history: [], dictionary: [])
}

struct AppPersistenceStore {
    private let directoryURL: URL
    private var fileURL: URL { directoryURL.appendingPathComponent("app-data.json") }

    init(directoryURL: URL? = nil) {
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            self.directoryURL = applicationSupport.appendingPathComponent("AkangVoiceInput", isDirectory: true)
        }
    }

    func load() throws -> AppDataSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        return try decoder.decode(AppDataSnapshot.self, from: data)
    }

    func save(_ snapshot: AppDataSnapshot) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
