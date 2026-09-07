import Foundation
import CoreGraphics

/// How far off the student was, moment by moment, across a whole attempt.
///
/// Sampled on the reference's clock at a fixed rate so the strip under the
/// scrubber and the scrubber itself share an x-axis. Built with the same
/// align-and-measure math the overlay draws with, so a red joint on screen and
/// a peak on the strip always agree. Never persisted — it is cheap to rebuild
/// and would only go stale if the error math changed.
struct AttemptTimeline: Equatable {
    struct Peak: Identifiable, Equatable {
        let id: Int
        let time: Double
        let error: Double
        let count: Int?
    }

    /// Samples per second on the reference clock.
    static let sampleRate: Double = 20
    /// Shoulders through feet. Face and finger landmarks would swamp the mean
    /// with detail nobody dances with.
    static let bodyJoints: [Int] = Array(11...16) + Array(23...32)

    let duration: Double
    /// `errors[i]` is the mean joint error at `i / sampleRate`; nil where too
    /// little of either body was visible to judge.
    let errors: [Double?]
    /// Worst moments, sorted by time.
    let peaks: [Peak]
    let maxError: Double

    // MARK: - Build

    static func build(reference: DanceRecording, attempt: DanceRecording, mirrored: Bool) -> AttemptTimeline {
        let duration = reference.effectiveFrameTimes.last ?? 0
        let sampleCount = max(1, Int(duration * sampleRate) + 1)

        var raw: [Double?] = []
        raw.reserveCapacity(sampleCount)
        for i in 0..<sampleCount {
            let time = Double(i) / sampleRate
            raw.append(sampleError(reference: reference, attempt: attempt, mirrored: mirrored, at: time))
        }

        let smoothed = smooth(raw)
        let peaks = findPeaks(in: smoothed, reference: reference)
        return AttemptTimeline(
            duration: duration,
            errors: smoothed,
            peaks: peaks,
            maxError: smoothed.compactMap { $0 }.max() ?? 0
        )
    }

    private static func sampleError(
        reference: DanceRecording,
        attempt: DanceRecording,
        mirrored: Bool,
        at time: Double
    ) -> Double? {
        guard let ref = PoseFeedback.interpolatedPose(of: reference, at: time), ref.count == 33 else { return nil }
        let attTime = PoseFeedback.attemptTime(forReferenceTime: time, reference: reference, attempt: attempt)
        guard var att = PoseFeedback.interpolatedPose(of: attempt, at: attTime), att.count == 33 else { return nil }

        if mirrored { att = PoseFeedback.mirrored(att) }
        let aligned = PoseFeedback.align(attempt: att, to: ref, mirrored: false)
        guard let errors = PoseFeedback.jointErrors(reference: ref, alignedAttempt: aligned) else { return nil }

        // jointErrors reports 0 for a joint the camera missed; averaging that
        // in would flatter the student, so only joints seen on both sides count.
        var total = 0.0
        var seen = 0
        for joint in bodyJoints where PoseFeedback.isValid(ref[joint]) && PoseFeedback.isValid(aligned[joint]) {
            total += errors[joint]
            seen += 1
        }
        guard seen >= 6 else { return nil }
        return total / Double(seen)
    }

    /// Three-tap moving average (0.15 s) so a single noisy frame can't read as
    /// a mistake. Gaps stay gaps.
    private static func smooth(_ series: [Double?]) -> [Double?] {
        series.indices.map { i in
            guard series[i] != nil else { return nil }
            var total = 0.0
            var count = 0
            for j in max(0, i - 1)...min(series.count - 1, i + 1) {
                if let value = series[j] { total += value; count += 1 }
            }
            return count > 0 ? total / Double(count) : nil
        }
    }

    private static func findPeaks(in series: [Double?], reference: DanceRecording) -> [Peak] {
        let threshold = 0.25          // about half a torso off, averaged over the body
        let minimumSeparation = 0.6   // seconds; one mistake, one peak
        let limit = 5

        var candidates: [(index: Int, error: Double)] = []
        for i in series.indices {
            guard let value = series[i], value >= threshold else { continue }
            let before = i > 0 ? (series[i - 1] ?? -1) : -1
            let after = i + 1 < series.count ? (series[i + 1] ?? -1) : -1
            if value >= before && value >= after {
                candidates.append((i, value))
            }
        }

        var chosen: [(index: Int, error: Double)] = []
        for candidate in candidates.sorted(by: { $0.error > $1.error }) {
            let tooClose = chosen.contains {
                abs(Double($0.index - candidate.index)) / sampleRate < minimumSeparation
            }
            if !tooClose { chosen.append(candidate) }
            if chosen.count >= limit { break }
        }

        // Nothing clearly wrong, but something was worst: still worth a marker,
        // so "worst at" always has an answer.
        if chosen.isEmpty {
            var best: (index: Int, error: Double)?
            for i in series.indices {
                if let value = series[i], value > (best?.error ?? 0.08) { best = (i, value) }
            }
            if let best { chosen.append(best) }
        }

        return chosen
            .sorted { $0.index < $1.index }
            .enumerated()
            .map { offset, item in
                let time = Double(item.index) / sampleRate
                return Peak(
                    id: offset,
                    time: time,
                    error: item.error,
                    count: LessonComparator.countLabel(forRefTime: time, reference: reference)
                )
            }
    }

    // MARK: - Lookup

    func error(at time: Double) -> Double? {
        let index = Int((time * AttemptTimeline.sampleRate).rounded())
        guard errors.indices.contains(index) else { return nil }
        return errors[index]
    }

    func peak(after time: Double) -> Peak? {
        peaks.first { $0.time > time + 0.05 }
    }

    func peak(before time: Double) -> Peak? {
        peaks.last { $0.time < time - 0.05 }
    }

    func nearestPeak(to time: Double, within tolerance: Double = 0.4) -> Peak? {
        peaks
            .filter { abs($0.time - time) <= tolerance }
            .min { abs($0.time - time) < abs($1.time - time) }
    }

    /// The most severe moment, for a headline when nothing is near the playhead.
    var worstPeak: Peak? {
        peaks.max { $0.error < $1.error }
    }
}
