import Foundation

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
        ((try? videosDirectoryURL()) ?? fileManager.temporaryDirectory)
            .appendingPathComponent(recording.videoFilename)
    }

    func existingVideoURL(for recording: DanceRecording) -> URL? {
        guard recording.hasVideo == true else { return nil }
        let url = videoURL(for: recording)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Links a saved recording to the post it became, so the profile does not show
    /// the same dance twice — once as a file and once as a post.
    func markPosted(_ recording: DanceRecording, videoID: Int) throws {
        var all = try load()
        guard let i = all.firstIndex(where: { $0.id == recording.id }) else { return }
        all[i].postedVideoID = videoID
        try save(all)
    }

    /// Breaks a link to a post that is no longer that dance — a deleted post
    /// whose id was handed to a later one.
    func unlinkPost(_ recording: DanceRecording) throws {
        var all = try load()
        guard let i = all.firstIndex(where: { $0.id == recording.id }) else { return }
        all[i].postedVideoID = nil
        try save(all)
    }

    private func save(_ recordings: [DanceRecording]) throws {
        let url = try recordingsURL()
        let data = try JSONEncoder().encode(recordings)
        try data.write(to: url, options: .atomic)
    }

    private func recordingsURL() throws -> URL {
        try AccountScope.directory().appendingPathComponent("recordings.json")
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
}
