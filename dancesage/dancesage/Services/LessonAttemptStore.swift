import Foundation

/// Keeps practice attempts on the device, one JSON file per lesson.
///
/// Per-lesson files rather than one big array: an attempt carries a full
/// skeleton track (~1 MB), so listing or deleting one lesson's attempts should
/// never decode every other lesson's.
@MainActor
final class LessonAttemptStore {
    static let shared = LessonAttemptStore()

    private let fileManager = FileManager.default

    private init() {}

    /// Newest first. Attempts written by a newer app version are skipped rather
    /// than failing the whole list.
    func attempts(forLesson lessonID: String) throws -> [LessonAttempt] {
        let url = try fileURL(forLesson: lessonID)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let attempts = try decoder().decode([LessonAttempt].self, from: Data(contentsOf: url))
        return attempts
            .filter { $0.formatVersion <= LessonAttempt.currentFormatVersion }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func add(_ attempt: LessonAttempt) throws -> [LessonAttempt] {
        var attempts = try attempts(forLesson: attempt.lessonID)
        attempts.insert(attempt, at: 0)
        try save(attempts, forLesson: attempt.lessonID)
        return attempts
    }

    /// Replaces the attempt with the same id, or adds it when there is none.
    @discardableResult
    func upsert(_ attempt: LessonAttempt) throws -> [LessonAttempt] {
        var attempts = try attempts(forLesson: attempt.lessonID)
        if let index = attempts.firstIndex(where: { $0.id == attempt.id }) {
            attempts[index] = attempt
        } else {
            attempts.insert(attempt, at: 0)
        }
        try save(attempts, forLesson: attempt.lessonID)
        return attempts
    }

    @discardableResult
    func delete(id: String, lessonID: String) throws -> [LessonAttempt] {
        var attempts = try attempts(forLesson: lessonID)
        if let gone = attempts.first(where: { $0.id == id }) { removeVideo(of: gone) }
        attempts.removeAll { $0.id == id }
        try save(attempts, forLesson: lessonID)
        return attempts
    }

    /// Removes every attempt for a lesson — called when the lesson itself goes.
    func deleteAll(forLesson lessonID: String) throws {
        let url = try fileURL(forLesson: lessonID)
        guard fileManager.fileExists(atPath: url.path) else { return }
        (try? attempts(forLesson: lessonID))?.forEach(removeVideo)
        try fileManager.removeItem(at: url)
    }

    /// Drops the attempt's video — unless it is really a saved recording's
    /// video that the attempt was compared from, which stays with the recording.
    private func removeVideo(of attempt: LessonAttempt) {
        let recordings = (try? RecordingStore.shared.load()) ?? []
        guard !recordings.contains(where: { $0.id == attempt.recording.id }) else { return }
        try? fileManager.removeItem(at: RecordingStore.shared.videoURL(for: attempt.recording))
    }

    private func save(_ attempts: [LessonAttempt], forLesson lessonID: String) throws {
        let url = try fileURL(forLesson: lessonID)
        try encoder().encode(attempts).write(to: url, options: .atomic)
    }

    private func fileURL(forLesson lessonID: String) throws -> URL {
        let directory = try AccountScope.directory().appendingPathComponent("Attempts", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(lessonID).json")
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
