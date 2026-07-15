import Foundation

@MainActor
final class RecordingStore {
    static let shared = RecordingStore()

    private let legacyKey = "savedDances"
    private let fileManager = FileManager.default

    private init() {}

    func load() throws -> [DanceRecording] {
        try migrateAccountRecordingsIfNeeded()
        try migrateLegacyRecordingsIfNeeded()
        let url = try recordingsURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([DanceRecording].self, from: Data(contentsOf: url))
    }

    func append(_ recording: DanceRecording, videoSourceURL: URL? = nil) throws {
        var recordings = try load()
        var copiedVideoURL: URL?
        if let videoSourceURL {
            let destination = try videosDirectoryURL().appendingPathComponent(recording.videoFilename)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: videoSourceURL, to: destination)
            copiedVideoURL = destination
        }
        recordings.append(recording)
        do {
            try save(recordings)
        } catch {
            if let copiedVideoURL { try? fileManager.removeItem(at: copiedVideoURL) }
            throw error
        }
    }

    func delete(at offsets: IndexSet) throws -> [DanceRecording] {
        var recordings = try load()
        for index in offsets.sorted(by: >) where recordings.indices.contains(index) {
            let recording = recordings.remove(at: index)
            if recording.hasVideo == true {
                try? fileManager.removeItem(at: videoURL(for: recording))
            }
        }
        try save(recordings)
        return recordings
    }

    func videoURL(for recording: DanceRecording) -> URL {
        let root = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return (root ?? fileManager.temporaryDirectory)
            .appendingPathComponent("DanceSage", isDirectory: true)
            .appendingPathComponent("Videos", isDirectory: true)
            .appendingPathComponent(recording.videoFilename)
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
        let directory = root
            .appendingPathComponent("DanceSage", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("recordings.json")
    }

    private func videosDirectoryURL() throws -> URL {
        let directory = try recordingsURL()
            .deletingLastPathComponent()
            .appendingPathComponent("Videos", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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

    private func migrateAccountRecordingsIfNeeded() throws {
        let destination = try recordingsURL()
        guard !fileManager.fileExists(atPath: destination.path) else { return }

        let root = destination.deletingLastPathComponent()
        let accountDirectories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var recordingsByID: [String: DanceRecording] = [:]
        for directory in accountDirectories {
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let accountFile = directory.appendingPathComponent("recordings.json")
            guard let data = try? Data(contentsOf: accountFile),
                  let recordings = try? JSONDecoder().decode([DanceRecording].self, from: data) else { continue }
            for recording in recordings {
                recordingsByID[recording.id] = recording
            }
        }

        guard !recordingsByID.isEmpty else { return }
        let recordings = recordingsByID.values.sorted { $0.timestamp < $1.timestamp }
        try JSONEncoder().encode(recordings).write(to: destination, options: .atomic)
    }
}
