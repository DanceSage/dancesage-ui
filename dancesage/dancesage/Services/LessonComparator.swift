import Foundation
import CoreGraphics

/// Compares a student attempt against a lesson's reference recording and produces
/// a score plus at most two spoken-friendly cues.
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
enum LessonComparator {

    // MARK: - Result types

    struct RegionResult: Identifiable {
        let region: Region
        /// Mean absolute angle deviation in degrees across compared samples.
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
        let dtwRescueMargin = 6.0
        var winner: (evaluation: Evaluation, byBeats: Bool)?
        switch (bestRigid, bestWarped) {
        case let (rigid?, warped?):
            winner = warped.evaluation.meanDeviation + dtwRescueMargin < rigid.evaluation.meanDeviation
                ? warped : rigid
        case let (rigid?, nil): winner = rigid
        case let (nil, warped?): winner = warped
        case (nil, nil): winner = nil
        }

        guard let winner else { throw ComparatorError.notEnoughData }
        let regions = winner.evaluation.regions
        let cues = makeCues(from: regions)
        return Result(
            overallScore: score(fromDeviation: winner.evaluation.meanDeviation),
            regions: regions,
            cues: cues,
            samplesCompared: winner.evaluation.samples,
            alignedByBeats: winner.byBeats,
            mirrored: winner.evaluation.isMirrored
        )
    }

    // MARK: - Time alignment

    private static func usesBeats(reference: DanceRecording, attempt: DanceRecording) -> Bool {
        (reference.beats?.count ?? 0) >= 4 && (attempt.beats?.count ?? 0) >= 4
    }

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
        if let refBeats = reference.beats, refBeats.count >= 2 {
            let passed = refBeats.filter { $0 <= time }.count
            return passed > 0 ? (passed - 1) % 8 + 1 : 1
        }
        return fallbackIndex % 8 + 1
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

    /// The eight comparator angles at each sample time; nil where the camera
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
            return angleSpecs.map { spec -> Double? in
                let a = mirrored ? mirrorMap[spec.a]! : spec.a
                let v = mirrored ? mirrorMap[spec.vertex]! : spec.vertex
                let c = mirrored ? mirrorMap[spec.c]! : spec.c
                guard isValid(pose[a]), isValid(pose[v]), isValid(pose[c]) else { return nil }
                return angle(at: pose[v], from: pose[a], to: pose[c])
            }
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

    /// MediaPipe 33-landmark indices for each measured angle: the angle sits at `vertex`.
    private struct AngleSpec {
        let region: Region
        let a: Int
        let vertex: Int
        let c: Int
        /// The angle whose signed deviation drives the region's cue wording.
        let isPrimary: Bool
    }

    private static let angleSpecs: [AngleSpec] = [
        // Arms: shoulder angle (arm elevation relative to torso) is primary; elbow refines it.
        AngleSpec(region: .leftArm, a: 13, vertex: 11, c: 23, isPrimary: true),
        AngleSpec(region: .leftArm, a: 11, vertex: 13, c: 15, isPrimary: false),
        AngleSpec(region: .rightArm, a: 14, vertex: 12, c: 24, isPrimary: true),
        AngleSpec(region: .rightArm, a: 12, vertex: 14, c: 16, isPrimary: false),
        // Legs: knee bend is primary; hip angle refines it.
        AngleSpec(region: .leftLeg, a: 23, vertex: 25, c: 27, isPrimary: true),
        AngleSpec(region: .leftLeg, a: 11, vertex: 23, c: 25, isPrimary: false),
        AngleSpec(region: .rightLeg, a: 24, vertex: 26, c: 28, isPrimary: true),
        AngleSpec(region: .rightLeg, a: 12, vertex: 24, c: 26, isPrimary: false),
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

    private static func angle(at rawVertex: CGPoint, from rawA: CGPoint, to rawC: CGPoint) -> Double? {
        let vertex = CGPoint(x: rawVertex.x * portraitAspect, y: rawVertex.y)
        let a = CGPoint(x: rawA.x * portraitAspect, y: rawA.y)
        let c = CGPoint(x: rawC.x * portraitAspect, y: rawC.y)
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
    }

    private static func evaluate(
        reference: DanceRecording,
        attempt: DanceRecording,
        times: [(ref: Double, att: Double, count: Int)],
        mirrored: Bool,
        lagTolerant: Bool = true
    ) -> Evaluation? {
        struct Accumulator {
            var absolute: [Double] = []
            var signedPrimary: [Double] = []
            var worstByCount: [Int: Double] = [:]
        }
        var accumulators: [Region: Accumulator] = [:]
        var comparedSamples = 0

        // A student following a reference reacts a beat-fraction late; grade the
        // best match within a small window instead of punishing reaction time.
        let lagOffsets: [Double] = lagTolerant ? [0, 0.15, 0.3, 0.45] : [0]

        for sample in times {
            guard let refIndex = frameIndex(at: sample.ref, in: reference),
                  let refPose = reference.keypoints[safe: refIndex]?.first,
                  refPose.count == 33 else { continue }

            var attPoseCandidate: [CGPoint]?
            var bestMean = Double.greatestFiniteMagnitude
            for offset in lagOffsets {
                guard let index = frameIndex(at: sample.att + offset, in: attempt),
                      let candidate = attempt.keypoints[safe: index]?.first,
                      candidate.count == 33 else { continue }
                var total = 0.0
                var count = 0
                for spec in angleSpecs {
                    let a = mirrored ? mirrorMap[spec.a]! : spec.a
                    let v = mirrored ? mirrorMap[spec.vertex]! : spec.vertex
                    let c = mirrored ? mirrorMap[spec.c]! : spec.c
                    guard isValid(refPose[spec.a]), isValid(refPose[spec.vertex]), isValid(refPose[spec.c]),
                          isValid(candidate[a]), isValid(candidate[v]), isValid(candidate[c]),
                          let refAngle = angle(at: refPose[spec.vertex], from: refPose[spec.a], to: refPose[spec.c]),
                          let attAngle = angle(at: candidate[v], from: candidate[a], to: candidate[c]) else { continue }
                    total += abs(attAngle - refAngle)
                    count += 1
                }
                guard count > 0 else { continue }
                let mean = total / Double(count)
                if mean < bestMean {
                    bestMean = mean
                    attPoseCandidate = candidate
                }
            }
            guard let attPose = attPoseCandidate else { continue }

            var sampleUsed = false
            for spec in angleSpecs {
                let attA = mirrored ? mirrorMap[spec.a]! : spec.a
                let attVertex = mirrored ? mirrorMap[spec.vertex]! : spec.vertex
                let attC = mirrored ? mirrorMap[spec.c]! : spec.c

                let refPoints = (refPose[spec.a], refPose[spec.vertex], refPose[spec.c])
                let attPoints = (attPose[attA], attPose[attVertex], attPose[attC])
                guard isValid(refPoints.0), isValid(refPoints.1), isValid(refPoints.2),
                      isValid(attPoints.0), isValid(attPoints.1), isValid(attPoints.2),
                      let refAngle = angle(at: refPoints.1, from: refPoints.0, to: refPoints.2),
                      let attAngle = angle(at: attPoints.1, from: attPoints.0, to: attPoints.2) else {
                    continue
                }

                let signed = attAngle - refAngle
                var accumulator = accumulators[spec.region, default: Accumulator()]
                accumulator.absolute.append(abs(signed))
                if spec.isPrimary {
                    accumulator.signedPrimary.append(signed)
                    let worst = accumulator.worstByCount[sample.count] ?? 0
                    accumulator.worstByCount[sample.count] = max(worst, abs(signed))
                }
                accumulators[spec.region] = accumulator
                sampleUsed = true
            }
            if sampleUsed { comparedSamples += 1 }
        }

        guard comparedSamples >= 4 else { return nil }

        var regionResults: [RegionResult] = []
        var allDeviations: [Double] = []
        for region in Region.allCases {
            guard let accumulator = accumulators[region], !accumulator.absolute.isEmpty else { continue }
            let mean = accumulator.absolute.reduce(0, +) / Double(accumulator.absolute.count)
            let signed = accumulator.signedPrimary.isEmpty
                ? 0
                : accumulator.signedPrimary.reduce(0, +) / Double(accumulator.signedPrimary.count)
            let worstCount = accumulator.worstByCount.max { $0.value < $1.value }?.key
            regionResults.append(RegionResult(
                region: region,
                meanDeviation: mean,
                signedPrimaryDeviation: signed,
                worstCount: worstCount
            ))
            allDeviations.append(contentsOf: accumulator.absolute)
        }

        guard !allDeviations.isEmpty else { return nil }
        let overallMean = allDeviations.reduce(0, +) / Double(allDeviations.count)
        return Evaluation(
            meanDeviation: overallMean,
            regions: regionResults.sorted { $0.meanDeviation > $1.meanDeviation },
            samples: comparedSamples,
            isMirrored: mirrored
        )
    }

    private static func score(fromDeviation degrees: Double) -> Int {
        // 0° off = 100. An average of 40° off across the body = 0.
        max(0, min(100, Int((1 - degrees / 40) * 100)))
    }

    // MARK: - Cues

    /// At most two cues, worst region first, and only when clearly off.
    /// Wording is written to be heard, not read.
    private static func makeCues(from regions: [RegionResult]) -> [String] {
        let cueThreshold = 12.0
        var cues: [String] = []

        for result in regions where result.meanDeviation > cueThreshold && cues.count < 2 {
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
            }
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
