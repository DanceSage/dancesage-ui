import Foundation

/// One practice run against a lesson: the student's skeleton plus the verdict.
///
/// Attempts stay on the phone until the student posts one, like any other
/// recording; `postedVideoID` then links the two, so the row can say so and
/// a re-post doesn't duplicate it.
struct LessonAttempt: Codable, Identifiable {
    static let currentFormatVersion = 1

    struct RegionScore: Codable {
        let region: String
        let score: Int
        let worstCount: Int?
    }

    let id: String
    let formatVersion: Int
    let lessonID: String
    let createdAt: Date
    /// The student's skeleton. No video, no world keypoints — the replay only
    /// needs 2D joints, frame times, and beats.
    let recording: DanceRecording
    let score: Int
    /// The comparator read the attempt better left/right flipped; the replay
    /// must flip the same way or the overlay grades the wrong limbs.
    let mirrored: Bool
    let alignedByBeats: Bool
    let cues: [String]
    let regions: [RegionScore]
    /// Optional so attempts saved before posting existed decode.
    var postedVideoID: Int?
    /// Sent to the teacher, from here or from the web.
    var sentToTeacher: Bool?

    init(lessonID: String, recording: DanceRecording, result: LessonComparator.Result) {
        self.id = UUID().uuidString
        self.formatVersion = LessonAttempt.currentFormatVersion
        self.lessonID = lessonID
        self.createdAt = Date()
        self.recording = recording
        self.score = result.overallScore
        self.mirrored = result.mirrored
        self.alignedByBeats = result.alignedByBeats
        self.cues = result.cues
        self.regions = result.regions.map {
            RegionScore(region: $0.region.rawValue, score: $0.score, worstCount: $0.worstCount)
        }
    }

    var isPosted: Bool { postedVideoID != nil }
}
