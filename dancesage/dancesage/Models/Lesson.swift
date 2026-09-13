import Foundation

/// A shareable lesson: a reference recording wrapped with teaching context.
///
/// Lessons travel as `.dancesage` files (JSON) through AirDrop, Messages, or any
/// share-sheet destination — no account or server involved. Video is deliberately
/// not included: the skeleton, frame times, and beats are everything comparison
/// and skeleton playback need, and keypoint JSON stays small enough to send in a
/// group chat.
struct Lesson: Codable, Identifiable {
    static let currentFormatVersion = 1
    static let fileExtension = "dancesage"

    let id: String
    let formatVersion: Int
    /// Settable: a lesson added before the post's owner travelled with it
    /// has no name, and the Lessons tab fills it in from the platform.
    var teacherName: String
    let note: String
    let createdAt: Date
    let recording: DanceRecording
    /// What the dancer called it when they made it. Optional so lessons saved
    /// before naming existed still decode — those fall back to the recording.
    /// Settable because adding a post you already have renames the lesson you
    /// have rather than making a second one.
    var name: String?
    /// Where it came from, when it came from a post: the video, and the group
    /// it was shared through. An attempt posted from this lesson answers that
    /// video and can go straight back to that group.
    var sourceVideoID: Int?
    var sourceGroupID: Int?
    var sourceGroupName: String?
    /// The series it came through, when it did — a folder in Lessons.
    var sourceSeriesName: String?
    /// The lesson's online id, when it came from a post.
    var onlineLessonID: Int?

    init(name: String? = nil, teacherName: String, note: String, recording: DanceRecording) {
        self.id = UUID().uuidString
        self.formatVersion = Lesson.currentFormatVersion
        self.teacherName = teacherName
        self.note = note
        self.createdAt = Date()
        self.recording = recording
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.name = trimmed.isEmpty ? nil : trimmed
    }

    var title: String { name ?? recording.name }
}
