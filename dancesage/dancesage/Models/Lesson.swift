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
    let teacherName: String
    let note: String
    let createdAt: Date
    let recording: DanceRecording

    init(teacherName: String, note: String, recording: DanceRecording) {
        self.id = UUID().uuidString
        self.formatVersion = Lesson.currentFormatVersion
        self.teacherName = teacherName
        self.note = note
        self.createdAt = Date()
        self.recording = recording
    }

    var title: String { recording.name }
}
