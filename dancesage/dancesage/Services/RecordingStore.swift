import Foundation
import FirebaseAuth

@MainActor
final class RecordingStore {
    static let shared = RecordingStore()

    private let legacyKey = "savedDances"
    private let fileManager = FileManager.default

    private init() {}

    func load() throws -> [DanceRecording] {
        try migrateLegacyRecordingsIfNeeded()
        let url = try recordingsURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([DanceRecording].self, from: Data(contentsOf: url))
    }

    func append(_ recording: DanceRecording) throws {
        var recordings = try load()
        recordings.append(recording)
        try save(recordings)
    }

    func delete(at offsets: IndexSet) throws -> [DanceRecording] {
        var recordings = try load()
        for index in offsets.sorted(by: >) where recordings.indices.contains(index) {
            recordings.remove(at: index)
        }
        try save(recordings)
        return recordings
    }

    private func save(_ recordings: [DanceRecording]) throws {
        let url = try recordingsURL()
        let data = try JSONEncoder().encode(recordings)
        try data.write(to: url, options: .atomic)
    }

    private func recordingsURL() throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let userID = Auth.auth().currentUser?.uid ?? "local"
        let directory = root
            .appendingPathComponent("DanceSage", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("recordings.json")
    }

    private func migrateLegacyRecordingsIfNeeded() throws {
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else { return }
        let destination = try recordingsURL()
        if !fileManager.fileExists(atPath: destination.path) {
            let recordings = try JSONDecoder().decode([DanceRecording].self, from: data)
            try JSONEncoder().encode(recordings).write(to: destination, options: .atomic)
        }
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}
