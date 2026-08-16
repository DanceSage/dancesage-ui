import Foundation

enum LessonStoreError: LocalizedError {
    case unreadable
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "This file is not a DanceSage lesson."
        case .unsupportedVersion(let version):
            return "This lesson needs a newer version of DanceSage (lesson format \(version))."
        }
    }
}

/// Stores imported lessons on the device, mirroring how RecordingStore keeps recordings.
@MainActor
final class LessonStore {
    static let shared = LessonStore()

    private let fileManager = FileManager.default

    private init() {}

    func load() throws -> [Lesson] {
        let url = try lessonsURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let lessons = try decoder().decode([Lesson].self, from: Data(contentsOf: url))
        return lessons.sorted { $0.createdAt > $1.createdAt }
    }

    /// Adds one of the dancer's own recordings straight into the lesson library —
    /// the one-phone path, no file sharing involved.
    @discardableResult
    func addLesson(recording: DanceRecording, teacherName: String) throws -> Lesson {
        let lesson = Lesson(teacherName: teacherName, note: "", recording: recording)
        var lessons = try load()
        lessons.append(lesson)
        try save(lessons)
        return lesson
    }

    /// Reads a shared `.dancesage` file and adds it to the library.
    /// Re-importing the same lesson replaces the stored copy rather than duplicating it.
    @discardableResult
    func importLesson(from fileURL: URL) throws -> Lesson {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: fileURL)
        let lesson: Lesson
        do {
            lesson = try decoder().decode(Lesson.self, from: data)
        } catch {
            throw LessonStoreError.unreadable
        }
        guard lesson.formatVersion <= Lesson.currentFormatVersion else {
            throw LessonStoreError.unsupportedVersion(lesson.formatVersion)
        }

        var lessons = try load()
        lessons.removeAll { $0.id == lesson.id }
        lessons.append(lesson)
        try save(lessons)
        return lesson
    }

    func delete(at offsets: IndexSet) throws -> [Lesson] {
        var lessons = try load()
        for index in offsets.sorted(by: >) where lessons.indices.contains(index) {
            lessons.remove(at: index)
        }
        try save(lessons)
        return lessons
    }

    /// Writes a recording as a shareable lesson file and returns its URL.
    func exportLessonFile(recording: DanceRecording, teacherName: String, note: String) throws -> URL {
        let lesson = Lesson(teacherName: teacherName, note: note, recording: recording)
        let data = try encoder().encode(lesson)

        let safeName = recording.name
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_")).inverted)
            .joined()
            .trimmingCharacters(in: .whitespaces)
        let base = safeName.isEmpty ? "DanceSage Lesson" : safeName
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("\(base).\(Lesson.fileExtension)")
        try? fileManager.removeItem(at: url)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func save(_ lessons: [Lesson]) throws {
        let url = try lessonsURL()
        try encoder().encode(lessons).write(to: url, options: .atomic)
    }

    private func lessonsURL() throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root.appendingPathComponent("DanceSage", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("lessons.json")
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
