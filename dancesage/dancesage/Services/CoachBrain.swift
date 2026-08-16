import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Turns the comparator's measured facts into natural coaching language using
/// Apple's on-device model when the device has it (Apple Intelligence, iOS 26+).
///
/// The model is a phrasing layer only: it may restate the measurements, never
/// invent technique — and on devices without it, the rule-based cues stand.
/// Nothing ever leaves the phone either way.
enum CoachBrain {

    /// A short spoken-style coaching paragraph, or nil when the on-device model
    /// is unavailable (caller falls back to the rule-based cues).
    static func naturalFeedback(
        for result: LessonComparator.Result,
        lessonName: String
    ) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }
        guard SystemLanguageModel.default.availability == .available else { return nil }

        let regionFacts = result.regions
            .map { region in
                var fact = "\(region.region.rawValue): \(region.score)/100"
                if let count = region.worstCount, region.meanDeviation > 12 {
                    fact += ", weakest around count \(count)"
                }
                return fact
            }
            .joined(separator: "; ")

        let facts = """
        Lesson: \(lessonName)
        Overall score: \(result.overallScore)/100
        Body regions — \(regionFacts)
        Measured corrections: \(result.cues.joined(separator: " "))
        """

        let session = LanguageModelSession(instructions: """
        You are a warm, encouraging salsa teacher giving spoken feedback right \
        after a student danced along with a reference. You will receive measured \
        facts about their attempt. Respond with two or three short spoken \
        sentences: acknowledge what went well, then the single most important \
        thing to fix, stated simply. Only restate the given measurements in \
        natural language — never invent dance technique, angles, or advice that \
        is not in the facts. No lists, no headings, plain speech.
        """)

        do {
            let response = try await session.respond(to: facts)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
