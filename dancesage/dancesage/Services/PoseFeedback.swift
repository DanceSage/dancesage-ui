import Foundation
import CoreGraphics

/// Geometry shared by the overlay replay and live ghost practice: anchoring an
/// attempt pose onto a reference pose, and measuring how far each joint is off.
enum PoseFeedback {

    /// Keypoints are normalized to the portrait frame, where one x-unit spans
    /// far fewer physical centimeters than one y-unit. All geometry must happen
    /// in physically proportional space or every distance and angle is warped.
    static let portraitAspect: CGFloat = 9.0 / 16.0

    static func toPhysical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * portraitAspect, y: p.y)
    }

    static func fromPhysical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / portraitAspect, y: p.y)
    }

    static func isValid(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.y >= 0
    }

    /// Mirrors (when needed), then anchors the attempt's hips onto the reference's
    /// hips and matches torso scale — so comparison is about shape, not where the
    /// dancer stood.
    static func align(attempt pose: [CGPoint], to referencePose: [CGPoint]?, mirrored: Bool) -> [CGPoint] {
        var pose = pose
        if mirrored {
            pose = pose.map { isValid($0) ? CGPoint(x: 1 - $0.x, y: $0.y) : $0 }
        }
        guard pose.count == 33, let refPose = referencePose, refPose.count == 33 else { return pose }

        // All alignment math happens in physical proportions.
        let phys = pose.map { isValid($0) ? toPhysical($0) : $0 }
        let physRef = refPose.map { isValid($0) ? toPhysical($0) : $0 }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard isValid(a), isValid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }

        guard let refHips = mid(physRef[23], physRef[24]),
              let refShoulders = mid(physRef[11], physRef[12]),
              let attHips = mid(phys[23], phys[24]),
              let attShoulders = mid(phys[11], phys[12]) else { return pose }

        let refTorso = distance(refShoulders, refHips)
        let attTorso = distance(attShoulders, attHips)
        guard attTorso > 0.001, refTorso > 0.001 else { return pose }
        let scale = refTorso / attTorso

        return phys.map { point in
            guard isValid(point) else { return point }
            return fromPhysical(CGPoint(
                x: (point.x - attHips.x) * scale + refHips.x,
                y: (point.y - attHips.y) * scale + refHips.y
            ))
        }
    }

    /// Within this many torso-lengths of the teacher's joint counts as matching —
    /// roughly 6 cm on an adult, which is pose-model jitter, not a mistake.
    static let matchingDistance = 0.12
    /// This far past `matchingDistance` reads fully red: about a quarter metre.
    static let fullyOffDistance = 0.45

    /// Per-joint error levels (0 = matching, 1 = badly off) for an attempt pose
    /// that has already been aligned onto the reference. Distances are normalized
    /// by the reference torso so body size and camera distance drop out.
    /// Joints the camera couldn't see return 0 — never judged.
    static func jointErrors(reference: [CGPoint], alignedAttempt: [CGPoint]) -> [Double]? {
        guard reference.count == 33, alignedAttempt.count == 33 else { return nil }

        let physRef = reference.map { isValid($0) ? toPhysical($0) : $0 }
        let physAtt = alignedAttempt.map { isValid($0) ? toPhysical($0) : $0 }

        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard isValid(a), isValid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        guard let refHips = mid(physRef[23], physRef[24]),
              let refShoulders = mid(physRef[11], physRef[12]) else { return nil }
        let torsoDx = refShoulders.x - refHips.x
        let torsoDy = refShoulders.y - refHips.y
        let torso = (torsoDx * torsoDx + torsoDy * torsoDy).squareRoot()
        guard torso > 0.001 else { return nil }

        return (0..<33).map { index in
            let ref = physRef[index]
            let att = physAtt[index]
            guard isValid(ref), isValid(att) else { return 0 }
            let dx = att.x - ref.x, dy = att.y - ref.y
            let distance = Double((dx * dx + dy * dy).squareRoot() / torso)
            let level = (distance - matchingDistance) / fullyOffDistance
            return min(1, max(0, level))
        }
    }

    // MARK: - Time lookup

    /// Index of the last frame at or before `seconds`; the first frame for
    /// anything earlier.
    static func frameIndex(at seconds: Double, in recording: DanceRecording) -> Int? {
        let times = recording.effectiveFrameTimes
        guard !times.isEmpty else { return nil }
        guard seconds > times[0] else { return 0 }
        var low = 0
        var high = times.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if times[middle] <= seconds { low = middle } else { high = middle - 1 }
        }
        return low
    }

    /// The pose at `seconds`, blended between the two frames that straddle it
    /// so slow-motion replay glides instead of stepping. A joint holds its
    /// earlier position when either frame lost it, and across a capture gap
    /// longer than half a second. Nil once the recording is over (plus a small
    /// tolerance) so a short attempt disappears rather than freezing.
    static func interpolatedPose(of recording: DanceRecording, at seconds: Double) -> [CGPoint]? {
        let times = recording.effectiveFrameTimes
        guard let index = frameIndex(at: seconds, in: recording),
              let current = recording.keypoints[safe: index]?.first else { return nil }
        if let end = times.last, seconds > end + 0.25 { return nil }

        let nextIndex = index + 1
        guard nextIndex < times.count,
              let next = recording.keypoints[safe: nextIndex]?.first,
              next.count == current.count else { return current }
        let span = times[nextIndex] - times[index]
        guard span > 0, span <= 0.5, seconds > times[index] else { return current }
        let fraction = CGFloat(min(1, (seconds - times[index]) / span))

        return zip(current, next).map { a, b in
            guard isValid(a), isValid(b) else { return a }
            return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
        }
    }

    /// Warps reference time onto the attempt's clock, beat interval by beat
    /// interval; by duration ratio when either side has no beats.
    static func attemptTime(
        forReferenceTime time: Double,
        reference: DanceRecording,
        attempt: DanceRecording
    ) -> Double {
        guard let refBeats = reference.beats, let attBeats = attempt.beats,
              refBeats.count >= 2, attBeats.count >= 2 else {
            let refDuration = reference.effectiveFrameTimes.last ?? 1
            let attDuration = attempt.effectiveFrameTimes.last ?? 1
            guard refDuration > 0 else { return 0 }
            return time / refDuration * attDuration
        }

        let n = min(refBeats.count, attBeats.count)
        if time <= refBeats[0] {
            // Before the first beat: shift by the difference in lead-in.
            return max(0, attBeats[0] - (refBeats[0] - time))
        }
        for i in 0..<(n - 1) {
            if time <= refBeats[i + 1] {
                let span = refBeats[i + 1] - refBeats[i]
                guard span > 0 else { return attBeats[i] }
                let fraction = (time - refBeats[i]) / span
                return attBeats[i] + fraction * (attBeats[i + 1] - attBeats[i])
            }
        }
        // Past the last shared beat: continue at the attempt's final tempo.
        return attBeats[n - 1] + (time - refBeats[n - 1])
    }

    /// Teacher and student as one two-person track on the teacher's clock:
    /// person 0 is the reference, person 1 the attempt warped onto it, flipped
    /// if the comparator read it mirrored, and anchored hip-to-hip. This is
    /// exactly what the replay draws — posted as-is, anyone with access sees
    /// the same two skeletons.
    static func overlayTrack(reference: DanceRecording, attempt: DanceRecording, mirrored: Bool) -> [[[CGPoint]]] {
        let times = reference.effectiveFrameTimes
        return times.enumerated().map { index, time in
            let ref = reference.keypoints[safe: index]?.first ?? []
            let attTime = attemptTime(forReferenceTime: time, reference: reference, attempt: attempt)
            guard var att = interpolatedPose(of: attempt, at: attTime) else { return [ref] }
            if mirrored { att = PoseFeedback.mirrored(att) }
            return [ref, align(attempt: att, to: ref.count == 33 ? ref : nil, mirrored: false)]
        }
    }

    private static let sidePairs: [(Int, Int)] = [
        (1, 4), (2, 5), (3, 6), (7, 8), (9, 10),
        (11, 12), (13, 14), (15, 16), (17, 18), (19, 20), (21, 22),
        (23, 24), (25, 26), (27, 28), (29, 30), (31, 32),
    ]

    /// Mirrors a pose's identity: flips x and swaps left/right landmark indices.
    static func mirrored(_ pose: [CGPoint]) -> [CGPoint] {
        guard pose.count == 33 else { return pose }
        var flipped = pose.map { isValid($0) ? CGPoint(x: 1 - $0.x, y: $0.y) : $0 }
        for (l, r) in sidePairs { flipped.swapAt(l, r) }
        return flipped
    }

    /// Per-joint values measured on a mirrored pose, put back onto the
    /// unmirrored landmarks — so a colour graded on the flipped skeleton lands
    /// on the right limb of the one drawn over the video.
    static func swapSides(_ values: [Double]) -> [Double] {
        guard values.count == 33 else { return values }
        var swapped = values
        for (l, r) in sidePairs { swapped.swapAt(l, r) }
        return swapped
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
