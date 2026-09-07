import Foundation
import CoreGraphics

/// Compares a student attempt against a lesson's reference recording and produces
/// a score plus a few spoken-friendly cues.
///
/// Design choices, in order of importance:
/// - **Joint angles, not positions.** Angles survive differences in body size,
///   camera distance, and framing that raw keypoints do not.
/// - **Beat-aligned sampling.** When both recordings carry detected beats, poses
///   are compared count-to-count — which is what dancers care about. Recordings
///   without beats fall back to normalized-time sampling.
/// - **Mirror tolerance.** A front-camera attempt of a rear-camera reference shows
///   up left/right swapped. Both interpretations are scored and the better one wins.
/// - **Confidence gating.** Joints the pose model did not see (negative sentinel
///   coordinates) are skipped, never corrected.
///
/// Strictness lives in `Strictness` below. Dancing is angles and timing; the
/// score is meant to be hard to please at this stage, and loosened deliberately.
enum LessonComparator {

    // MARK: - Strictness

    /// Every tolerance in one place.
    enum Strictness {
        /// Deviation below this is pose-model jitter, not dancing. A still person
        /// measures 2–4° of noise; nothing under the floor costs points.
        static let noiseFloorDegrees = 3.0
        /// Typical (RMS) deviation past the floor that scores zero. 28° total
        /// means an arm held at the wrong height across the whole dance is a
        /// failed attempt, not a 70.
        static let zeroScoreDegrees = 25.0
        /// How late the student may react before it counts. Following a ghost
        /// costs a frame or two; more than that is being behind the music.
        static let lagOffsets: [Double] = [0, 0.1, 0.2]
        /// Points lost for averaging this far behind the reference.
        static let latePenaltyPerSecond = 50.0
        static let maxLatePenalty = 10
        /// Region deviation that earns a spoken cue.
        static let cueThresholdDegrees = 8.0
        /// Mean lag that earns a timing cue.
        static let lateCueSeconds = 0.12
        /// DTW may only replace rigid alignment when it fits this much better.
        static let dtwRescueMarginDegrees = 6.0
    }

    // MARK: - Result types

    struct RegionResult: Identifiable {
        let region: Region
        /// Typical (RMS) angle deviation in degrees across compared samples.
        let meanDeviation: Double
        /// Mean signed deviation (attempt minus reference) of the region's primary
        /// angle; the sign picks the cue's direction.
        let signedPrimaryDeviation: Double
        /// 1-based count (within the 8-count) where the region was furthest off.
        let worstCount: Int?

        var id: String { region.rawValue }
        var score: Int { LessonComparator.score(fromDeviation: meanDeviation) }
    }

    struct Result {
        let overallScore: Int
        let regions: [RegionResult]
        let cues: [String]
        let samplesCompared: Int
        let alignedByBeats: Bool
        let mirrored: Bool
        /// Typical angle error across the body, in degrees — the number the score
        /// is made from.
        let typicalDeviation: Double
        /// How far behind the reference the student ran, on average.
        let meanLagSeconds: Double
    }

    enum ComparatorError: LocalizedError {
        case notEnoughData

        var errorDescription: String? {
            "Not enough matching pose data to compare. Make sure your whole body is visible and try again."
        }
    }

    enum Region: String, CaseIterable {
        case leftArm = "Left arm"
        case rightArm = "Right arm"
        case leftLeg = "Left leg"
        case rightLeg = "Right leg"
        case posture = "Posture"
    }

    // MARK: - Public entry

    static func compare(reference: DanceRecording, attempt: DanceRecording) throws -> Result {
        // Candidate time alignments. Beats are used when present, but never
        // trusted blindly: dynamic time warping aligns by the movement itself,
        // and whichever alignment fits the dancing best wins. Bad or missing
        // beat detection can therefore no longer poison the match.
        var candidates: [(times: [(ref: Double, att: Double, count: Int)], byBeats: Bool, mirrored: Bool, lagTolerant: Bool)] = []

        let beatTimes = beatSampleTimes(reference: reference, attempt: attempt)
        let uniformTimes = uniformSampleTimes(reference: reference, attempt: attempt)
        for flag in [false, true] {
            if let beatTimes { candidates.append((beatTimes, true, flag, true)) }
            candidates.append((uniformTimes, false, flag, true))
            // DTW already flexes time; giving it the reaction-lag window too
            // would let temporal freedom launder real spatial errors.
            if let dtwTimes = dtwSampleTimes(reference: reference, attempt: attempt, mirrored: flag) {
                candidates.append((dtwTimes, false, flag, false))
            }
        }

        var bestRigid: (evaluation: Evaluation, byBeats: Bool)?
        var bestWarped: (evaluation: Evaluation, byBeats: Bool)?
        for candidate in candidates where candidate.times.count >= 4 {
            guard let evaluation = evaluate(
                reference: reference,
                attempt: attempt,
                times: candidate.times,
                mirrored: candidate.mirrored,
                lagTolerant: candidate.lagTolerant
            ) else { continue }
            if candidate.lagTolerant {
                if bestRigid == nil || evaluation.meanDeviation < bestRigid!.evaluation.meanDeviation {
                    bestRigid = (evaluation, candidate.byBeats)
                }
            } else {
                if bestWarped == nil || evaluation.meanDeviation < bestWarped!.evaluation.meanDeviation {
                    bestWarped = (evaluation, candidate.byBeats)
                }
            }
        }

        // DTW is a rescue for broken clocks (bad beats, late starts), not a
        // competitor: on a repetitive dance it can warp a real spatial error
        // away. It wins only when rigid alignment has clearly failed.
        var winner: (evaluation: Evaluation, byBeats: Bool)?
        switch (bestRigid, bestWarped) {
        case let (rigid?, warped?):
            winner = warped.evaluation.meanDeviation + Strictness.dtwRescueMarginDegrees < rigid.evaluation.meanDeviation
                ? warped : rigid
        case let (rigid?, nil): winner = rigid
        case let (nil, warped?): winner = warped
        case (nil, nil): winner = nil
        }

        guard let winner else { throw ComparatorError.notEnoughData }
        let regions = winner.evaluation.regions
        let lag = winner.evaluation.meanLag
        let cues = makeCues(from: regions, meanLag: lag)
        let latePenalty = min(Strictness.maxLatePenalty, Int(lag * Strictness.latePenaltyPerSecond))
        return Result(
            overallScore: max(0, score(fromDeviation: winner.evaluation.meanDeviation) - latePenalty),
            regions: regions,
            cues: cues,
            samplesCompared: winner.evaluation.samples,
            alignedByBeats: winner.byBeats,
            mirrored: winner.evaluation.isMirrored,
            typicalDeviation: winner.evaluation.meanDeviation,
            meanLagSeconds: lag
        )
    }

    // MARK: - Time alignment

    /// Beat-paired sample times, when both recordings carry usable beats.
    private static func beatSampleTimes(
        reference: DanceRecording,
        attempt: DanceRecording
    ) -> [(ref: Double, att: Double, count: Int)]? {
        guard let refBeats = reference.beats, let attBeats = attempt.beats,
              refBeats.count >= 4, attBeats.count >= 4 else { return nil }
        let n = min(refBeats.count, attBeats.count)
        var samples: [(Double, Double, Int)] = []
        for i in 0..<n {
            samples.append((refBeats[i], attBeats[i], i % 8 + 1))
            // A midpoint between counts keeps transitions honest, not just poses.
            if i + 1 < n {
                samples.append((
                    (refBeats[i] + refBeats[i + 1]) / 2,
                    (attBeats[i] + attBeats[i + 1]) / 2,
                    i % 8 + 1
                ))
            }
        }
        return samples
    }

    /// Uniform stretch of the attempt onto the reference over normalized time.
    private static func uniformSampleTimes(
        reference: DanceRecording,
        attempt: DanceRecording
    ) -> [(ref: Double, att: Double, count: Int)] {
        let refDuration = reference.effectiveFrameTimes.last ?? 0
        let attDuration = attempt.effectiveFrameTimes.last ?? 0
        guard refDuration > 0, attDuration > 0 else { return [] }
        return (0..<24).map { i in
            let t = Double(i) / 23.0
            return (t * refDuration, t * attDuration, countLabel(forRefTime: t * refDuration, reference: reference, fallbackIndex: i))
        }
    }

    /// Count number for a reference time — from the reference's beats when it
    /// has them, otherwise a rolling index.
    private static func countLabel(forRefTime time: Double, reference: DanceRecording, fallbackIndex: Int) -> Int {
        countLabel(forRefTime: time, reference: reference) ?? fallbackIndex % 8 + 1
    }

    /// 1-based position within the 8-count at a reference time; nil when the
    /// reference carries no beats to count against.
    static func countLabel(forRefTime time: Double, reference: DanceRecording) -> Int? {
        guard let refBeats = reference.beats, refBeats.count >= 2 else { return nil }
        let passed = refBeats.filter { $0 <= time }.count
        return passed > 0 ? (passed - 1) % 8 + 1 : 1
    }

    // MARK: - Dynamic time warping

    /// Aligns the two dances by the movement itself: joint-angle feature vectors
    /// sampled along each recording, warped with a banded DTW. Works with wrong
    /// beats, missing beats, late starts, and tempo drift.
    private static func dtwSampleTimes(
        reference: DanceRecording,
        attempt: DanceRecording,
        mirrored: Bool
    ) -> [(ref: Double, att: Double, count: Int)]? {
        let step = 0.15
        let refDuration = reference.effectiveFrameTimes.last ?? 0
        let attDuration = attempt.effectiveFrameTimes.last ?? 0
        guard refDuration > step * 4, attDuration > step * 4 else { return nil }

        let refTimes = stride(from: 0.0, through: min(refDuration, 60), by: step).map { $0 }
        let attTimes = stride(from: 0.0, through: min(attDuration, 60), by: step).map { $0 }
        let refFeatures = angleFeatures(of: reference, at: refTimes, mirrored: false)
        let attFeatures = angleFeatures(of: attempt, at: attTimes, mirrored: mirrored)

        let n = refTimes.count
        let m = attTimes.count
        guard n >= 4, m >= 4 else { return nil }

        func cost(_ i: Int, _ j: Int) -> Double {
            var total = 0.0
            var count = 0
            for k in 0..<angleSpecs.count {
                guard let a = refFeatures[i][k], let b = attFeatures[j][k] else { continue }
                total += abs(a - b)
                count += 1
            }
            return count > 0 ? total / Double(count) : 90
        }

        // Banded DP so the warp can't degenerate.
        let band = max(12, Int(0.35 * Double(max(n, m))))
        let infinity = Double.greatestFiniteMagnitude
        var dp = [[Double]](repeating: [Double](repeating: infinity, count: m), count: n)
        var from = [[Int8]](repeating: [Int8](repeating: 0, count: m), count: n) // 1 diag, 2 up, 3 left
        for i in 0..<n {
            let center = i * m / n
            for j in max(0, center - band)...min(m - 1, center + band) {
                let c = cost(i, j)
                if i == 0 && j == 0 { dp[0][0] = c; continue }
                var bestPrev = infinity
                var move: Int8 = 0
                if i > 0, j > 0, dp[i-1][j-1] < bestPrev { bestPrev = dp[i-1][j-1]; move = 1 }
                if i > 0, dp[i-1][j] < bestPrev { bestPrev = dp[i-1][j]; move = 2 }
                if j > 0, dp[i][j-1] < bestPrev { bestPrev = dp[i][j-1]; move = 3 }
                guard bestPrev < infinity else { continue }
                dp[i][j] = bestPrev + c
                from[i][j] = move
            }
        }
        guard dp[n-1][m-1] < infinity else { return nil }

        // Backtrack the warp path.
        var path: [(Int, Int)] = []
        var i = n - 1, j = m - 1
        while true {
            path.append((i, j))
            if i == 0 && j == 0 { break }
            switch from[i][j] {
            case 1: i -= 1; j -= 1
            case 2: i -= 1
            case 3: j -= 1
            default: return nil // fell off the band
            }
        }
        path.reverse()

        // ~28 evenly spaced pairs along the path.
        let targetCount = 28
        let strideLength = max(1, path.count / targetCount)
        var samples: [(Double, Double, Int)] = []
        for (position, pair) in path.enumerated()
        where position % strideLength == 0 || position == path.count - 1 {
            samples.append((
                refTimes[pair.0],
                attTimes[pair.1],
                countLabel(forRefTime: refTimes[pair.0], reference: reference, fallbackIndex: samples.count)
            ))
        }
        return samples.count >= 4 ? samples : nil
    }

    /// Every comparator angle at each sample time; nil where the camera
    /// couldn't see a joint.
    private static func angleFeatures(
        of recording: DanceRecording,
        at times: [Double],
        mirrored: Bool
    ) -> [[Double?]] {
        times.map { time in
            guard let index = frameIndex(at: time, in: recording),
                  let pose = recording.keypoints[safe: index]?.first,
                  pose.count == 33 else {
                return [Double?](repeating: nil, count: angleSpecs.count)
            }
            return angleSpecs.map { measure($0, in: pose, mirrored: mirrored) }
        }
    }

    private static func frameIndex(at seconds: Double, in recording: DanceRecording) -> Int? {
        let times = recording.effectiveFrameTimes
        guard !times.isEmpty else { return nil }
        guard seconds >= times[0] else { return 0 }
        var low = 0
        var high = times.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if times[middle] <= seconds { low = middle } else { high = middle - 1 }
        }
        return low
    }

    // MARK: - Angles

    /// What one measurement is. Joint angles sit at a vertex between two other
    /// landmarks; posture angles are taken against the frame itself.
    private enum Measurement {
        /// MediaPipe 33-landmark indices; the angle sits at `vertex`.
        case joint(a: Int, vertex: Int, c: Int)
        /// Hip-midpoint → shoulder-midpoint, degrees from vertical.
        case torsoLean
        /// Shoulder line, degrees from horizontal.
        case shoulderLine
    }

    private struct AngleSpec {
        let region: Region
        let measurement: Measurement
        /// The angle whose signed deviation drives the region's cue wording.
        let isPrimary: Bool
    }

    private static let angleSpecs: [AngleSpec] = [
        // Arms: shoulder angle (upper arm vs torso) is primary — it is the height
        // of the arm. Whole-arm direction (wrist vs torso) catches a bent elbow
        // held at the right shoulder angle; the elbow angle refines both.
        AngleSpec(region: .leftArm, measurement: .joint(a: 13, vertex: 11, c: 23), isPrimary: true),
        AngleSpec(region: .leftArm, measurement: .joint(a: 15, vertex: 11, c: 23), isPrimary: false),
        AngleSpec(region: .leftArm, measurement: .joint(a: 11, vertex: 13, c: 15), isPrimary: false),
        AngleSpec(region: .rightArm, measurement: .joint(a: 14, vertex: 12, c: 24), isPrimary: true),
        AngleSpec(region: .rightArm, measurement: .joint(a: 16, vertex: 12, c: 24), isPrimary: false),
        AngleSpec(region: .rightArm, measurement: .joint(a: 12, vertex: 14, c: 16), isPrimary: false),
        // Legs: knee bend is primary; hip angle places the leg, ankle angle is
        // the footwork — a flexed foot and a pointed one are different steps.
        AngleSpec(region: .leftLeg, measurement: .joint(a: 23, vertex: 25, c: 27), isPrimary: true),
        AngleSpec(region: .leftLeg, measurement: .joint(a: 11, vertex: 23, c: 25), isPrimary: false),
        AngleSpec(region: .leftLeg, measurement: .joint(a: 25, vertex: 27, c: 31), isPrimary: false),
        AngleSpec(region: .rightLeg, measurement: .joint(a: 24, vertex: 26, c: 28), isPrimary: true),
        AngleSpec(region: .rightLeg, measurement: .joint(a: 12, vertex: 24, c: 26), isPrimary: false),
        AngleSpec(region: .rightLeg, measurement: .joint(a: 26, vertex: 28, c: 32), isPrimary: false),
        // Posture: how much the torso leans, and whether the shoulders are level.
        AngleSpec(region: .posture, measurement: .torsoLean, isPrimary: true),
        AngleSpec(region: .posture, measurement: .shoulderLine, isPrimary: false),
    ]

    /// Left/right landmark swap, used to test the mirrored interpretation.
    private static let mirrorMap: [Int: Int] = {
        let pairs: [(Int, Int)] = [
            (1, 4), (2, 5), (3, 6), (7, 8), (9, 10),
            (11, 12), (13, 14), (15, 16), (17, 18), (19, 20), (21, 22),
            (23, 24), (25, 26), (27, 28), (29, 30), (31, 32),
        ]
        var map: [Int: Int] = [0: 0]
        for (l, r) in pairs {
            map[l] = r
            map[r] = l
        }
        return map
    }()

    private static func isValid(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.y >= 0
    }

    /// Portrait aspect correction — angles measured in raw normalized
    /// coordinates are warped because x- and y-units differ physically.
    private static let portraitAspect: CGFloat = 9.0 / 16.0

    private static func physical(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * portraitAspect, y: p.y)
    }

    /// One measurement on one pose, or nil when the camera missed a landmark
    /// it needs. Posture angles are unsigned, so they read the same mirrored.
    private static func measure(_ spec: AngleSpec, in pose: [CGPoint], mirrored: Bool) -> Double? {
        func landmark(_ index: Int) -> CGPoint? {
            let mapped = mirrored ? mirrorMap[index]! : index
            let point = pose[mapped]
            return isValid(point) ? point : nil
        }
        switch spec.measurement {
        case let .joint(a, vertex, c):
            guard let a = landmark(a), let v = landmark(vertex), let c = landmark(c) else { return nil }
            return angle(at: v, from: a, to: c)
        case .torsoLean:
            guard let ls = landmark(11), let rs = landmark(12),
                  let lh = landmark(23), let rh = landmark(24) else { return nil }
            let shoulders = physical(CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2))
            let hips = physical(CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2))
            return directionAngle(dx: shoulders.x - hips.x, dy: shoulders.y - hips.y, againstVertical: true)
        case .shoulderLine:
            guard let ls = landmark(11), let rs = landmark(12) else { return nil }
            let a = physical(ls), b = physical(rs)
            return directionAngle(dx: b.x - a.x, dy: b.y - a.y, againstVertical: false)
        }
    }

    /// Unsigned angle of a direction from the vertical or horizontal axis, 0–90.
    private static func directionAngle(dx: CGFloat, dy: CGFloat, againstVertical: Bool) -> Double? {
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0.0001 else { return nil }
        let along = againstVertical ? abs(dy) : abs(dx)
        let clamped = Double(max(-1, min(1, along / length)))
        return acos(clamped) * 180 / Double.pi
    }

    private static func angle(at rawVertex: CGPoint, from rawA: CGPoint, to rawC: CGPoint) -> Double? {
        let vertex = physical(rawVertex)
        let a = physical(rawA)
        let c = physical(rawC)
        let v1 = CGPoint(x: a.x - vertex.x, y: a.y - vertex.y)
        let v2 = CGPoint(x: c.x - vertex.x, y: c.y - vertex.y)
        let len1 = (v1.x * v1.x + v1.y * v1.y).squareRoot()
        let len2 = (v2.x * v2.x + v2.y * v2.y).squareRoot()
        guard len1 > 0.0001, len2 > 0.0001 else { return nil }
        let dot = (v1.x * v2.x + v1.y * v2.y) / (len1 * len2)
        let clamped = Double(max(-1, min(1, dot)))
        return acos(clamped) * 180 / Double.pi
    }

    // MARK: - Evaluation

    private struct Evaluation {
        let meanDeviation: Double
        let regions: [RegionResult]
        let samples: Int
        let isMirrored: Bool
        let meanLag: Double
    }

    private static func evaluate(
        reference: DanceRecording,
        attempt: DanceRecording,
        times: [(ref: Double, att: Double, count: Int)],
        mirrored: Bool,
        lagTolerant: Bool = true
    ) -> Evaluation? {
        struct Accumulator {
            var squared: [Double] = []
            var signedPrimary: [Double] = []
            var worstByCount: [Int: Double] = [:]
        }
        var accumulators: [Region: Accumulator] = [:]
        var comparedSamples = 0
        var lagTotal = 0.0

        // A student following a reference reacts a little late; grade the best
        // match within a short window, and remember how late it was.
        let lagOffsets: [Double] = lagTolerant ? Strictness.lagOffsets : [0]

        for sample in times {
            guard let refIndex = frameIndex(at: sample.ref, in: reference),
                  let refPose = reference.keypoints[safe: refIndex]?.first,
                  refPose.count == 33 else { continue }
            let refAngles = angleSpecs.map { measure($0, in: refPose, mirrored: false) }

            var bestAngles: [Double?]?
            var bestMean = Double.greatestFiniteMagnitude
            var bestOffset = 0.0
            for offset in lagOffsets {
                guard let index = frameIndex(at: sample.att + offset, in: attempt),
                      let candidate = attempt.keypoints[safe: index]?.first,
                      candidate.count == 33 else { continue }
                let attAngles = angleSpecs.map { measure($0, in: candidate, mirrored: mirrored) }
                var total = 0.0
                var count = 0
                for k in angleSpecs.indices {
                    guard let r = refAngles[k], let a = attAngles[k] else { continue }
                    total += abs(a - r)
                    count += 1
                }
                guard count > 0 else { continue }
                let mean = total / Double(count)
                if mean < bestMean {
                    bestMean = mean
                    bestAngles = attAngles
                    bestOffset = offset
                }
            }
            guard let attAngles = bestAngles else { continue }

            var sampleUsed = false
            for (k, spec) in angleSpecs.enumerated() {
                guard let refAngle = refAngles[k], let attAngle = attAngles[k] else { continue }
                let signed = attAngle - refAngle
                var accumulator = accumulators[spec.region, default: Accumulator()]
                accumulator.squared.append(signed * signed)
                if spec.isPrimary {
                    accumulator.signedPrimary.append(signed)
                    let worst = accumulator.worstByCount[sample.count] ?? 0
                    accumulator.worstByCount[sample.count] = max(worst, abs(signed))
                }
                accumulators[spec.region] = accumulator
                sampleUsed = true
            }
            if sampleUsed {
                comparedSamples += 1
                lagTotal += bestOffset
            }
        }

        guard comparedSamples >= 4 else { return nil }

        var regionResults: [RegionResult] = []
        var allSquared: [Double] = []
        for region in Region.allCases {
            guard let accumulator = accumulators[region], !accumulator.squared.isEmpty else { continue }
            let rms = (accumulator.squared.reduce(0, +) / Double(accumulator.squared.count)).squareRoot()
            let signed = accumulator.signedPrimary.isEmpty
                ? 0
                : accumulator.signedPrimary.reduce(0, +) / Double(accumulator.signedPrimary.count)
            let worstCount = accumulator.worstByCount.max { $0.value < $1.value }?.key
            regionResults.append(RegionResult(
                region: region,
                meanDeviation: rms,
                signedPrimaryDeviation: signed,
                worstCount: worstCount
            ))
            allSquared.append(contentsOf: accumulator.squared)
        }

        guard !allSquared.isEmpty else { return nil }
        // Root-mean-square, not the mean: one limb badly wrong for a whole
        // phrase should cost more than everything being slightly off.
        let overall = (allSquared.reduce(0, +) / Double(allSquared.count)).squareRoot()
        return Evaluation(
            meanDeviation: overall,
            regions: regionResults.sorted { $0.meanDeviation > $1.meanDeviation },
            samples: comparedSamples,
            isMirrored: mirrored,
            meanLag: lagTotal / Double(comparedSamples)
        )
    }

    /// Nothing under the noise floor costs; every degree past it costs the same,
    /// down to zero at `noiseFloor + zeroScore` degrees.
    private static func score(fromDeviation degrees: Double) -> Int {
        let past = max(0, degrees - Strictness.noiseFloorDegrees)
        return max(0, min(100, Int(((1 - past / Strictness.zeroScoreDegrees) * 100).rounded())))
    }

    // MARK: - Cues

    /// At most two body cues, worst region first, plus a timing cue when the
    /// student ran behind. Wording is written to be heard, not read.
    private static func makeCues(from regions: [RegionResult], meanLag: Double) -> [String] {
        var cues: [String] = []

        for result in regions where result.meanDeviation > Strictness.cueThresholdDegrees && cues.count < 2 {
            let name = result.region.rawValue.lowercased()
            let countSuffix: String
            if let count = result.worstCount {
                countSuffix = ", especially around count \(count)"
            } else {
                countSuffix = ""
            }

            switch result.region {
            case .leftArm, .rightArm:
                if result.signedPrimaryDeviation < 0 {
                    cues.append("Lift your \(name) higher\(countSuffix).")
                } else {
                    cues.append("Bring your \(name) closer to your body\(countSuffix).")
                }
            case .leftLeg, .rightLeg:
                if result.signedPrimaryDeviation > 0 {
                    cues.append("Bend your \(name) more\(countSuffix).")
                } else {
                    cues.append("Straighten your \(name) a little more\(countSuffix).")
                }
            case .posture:
                if result.signedPrimaryDeviation > 0 {
                    cues.append("Stand taller — you're leaning more than the teacher\(countSuffix).")
                } else {
                    cues.append("Match the teacher's lean — you're staying too upright\(countSuffix).")
                }
            }
        }

        if meanLag >= Strictness.lateCueSeconds {
            let tenths = Int((meanLag * 10).rounded())
            cues.append("You're running behind the music — about \(max(tenths, 1)) tenth\(tenths == 1 ? "" : "s") of a second late. Anticipate the next move.")
        }

        if cues.isEmpty {
            cues.append("Nice work. Your movement is close to the reference — keep polishing the details.")
        }
        return cues
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
