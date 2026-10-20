import CoreGraphics
import Foundation
import Vision

/// Converts Vision observations into two stable dancer tracks shared by live
/// capture and imported-video processing.
final class PartnerPoseTracker {
    private struct Candidate {
        let points: [CGPoint]
        let center: CGPoint
        let score: Float
    }

    private struct Track {
        var points: [CGPoint]
        var center: CGPoint
        var velocity: CGVector
        var missedFrames: Int
    }

    private let lock = NSLock()
    private var tracks: [Track?] = [nil, nil]

    private let minimumJointConfidence: Float = 0.25
    private let minimumValidJoints = 6
    private let maximumMatchDistance: CGFloat = 0.42
    private let framesToHoldOccludedPose = 3

    private let jointOrder: [VNHumanBodyPoseObservation.JointName] = [
        .nose, .leftEye, .rightEye, .leftEar, .rightEar,
        .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
        .leftWrist, .rightWrist, .leftHip, .rightHip,
        .leftKnee, .rightKnee, .leftAnkle, .rightAnkle
    ]

    func reset() {
        lock.lock()
        tracks = [nil, nil]
        lock.unlock()
    }

    func update(with observations: [VNHumanBodyPoseObservation]) -> [[CGPoint]] {
        lock.lock()
        defer { lock.unlock() }

        var candidates = observations.compactMap(makeCandidate)
            .sorted { $0.score > $1.score }
        if candidates.count > 2 {
            candidates.removeSubrange(2...)
        }

        if tracks.allSatisfy({ $0 == nil }) {
            candidates.sort { $0.center.x < $1.center.x }
            for (index, candidate) in candidates.enumerated() {
                tracks[index] = makeTrack(from: candidate)
            }
            return visibleTracks()
        }

        var assignments: [Int: Int] = [:]
        var unusedCandidateIndices = Set(candidates.indices)
        let activeTrackIndices = tracks.indices.filter { tracks[$0] != nil }

        // With two established dancers, compare both possible assignments.
        // Predicted centers make identity less likely to swap as partners cross.
        if activeTrackIndices.count == 2, candidates.count == 2 {
            let first = activeTrackIndices[0]
            let second = activeTrackIndices[1]
            let direct = matchDistance(track: first, candidate: candidates[0])
                + matchDistance(track: second, candidate: candidates[1])
            let crossed = matchDistance(track: first, candidate: candidates[1])
                + matchDistance(track: second, candidate: candidates[0])

            if direct <= crossed {
                assignments[first] = 0
                assignments[second] = 1
            } else {
                assignments[first] = 1
                assignments[second] = 0
            }
            unusedCandidateIndices.removeAll()
        } else {
            // Match the strongest remaining track/candidate pair first.
            var pairs: [(distance: CGFloat, track: Int, candidate: Int)] = []
            for trackIndex in activeTrackIndices {
                for candidateIndex in candidates.indices {
                    pairs.append((
                        matchDistance(track: trackIndex, candidate: candidates[candidateIndex]),
                        trackIndex,
                        candidateIndex
                    ))
                }
            }
            pairs.sort { $0.distance < $1.distance }

            for pair in pairs where pair.distance <= maximumMatchDistance {
                guard assignments[pair.track] == nil,
                      unusedCandidateIndices.contains(pair.candidate) else { continue }
                assignments[pair.track] = pair.candidate
                unusedCandidateIndices.remove(pair.candidate)
            }
        }

        // New dancers enter empty slots. Keeping two fixed slots preserves each
        // dancer's overlay color even when the other dancer briefly disappears.
        var emptyTrackIndices = tracks.indices.filter { tracks[$0] == nil }
        for candidateIndex in unusedCandidateIndices.sorted() {
            if let emptyTrack = emptyTrackIndices.first {
                assignments[emptyTrack] = candidateIndex
                emptyTrackIndices.removeFirst()
            }
        }

        for trackIndex in tracks.indices {
            if let candidateIndex = assignments[trackIndex] {
                updateTrack(at: trackIndex, with: candidates[candidateIndex])
            } else if var track = tracks[trackIndex] {
                track.missedFrames += 1
                track.velocity.dx *= 0.5
                track.velocity.dy *= 0.5
                tracks[trackIndex] = track.missedFrames <= framesToHoldOccludedPose ? track : nil
            }
        }

        return visibleTracks()
    }

    private func makeCandidate(from observation: VNHumanBodyPoseObservation) -> Candidate? {
        var confidenceTotal: Float = 0
        var validJointCount = 0

        let points = jointOrder.map { joint -> CGPoint in
            guard let point = try? observation.recognizedPoint(joint),
                  point.confidence >= minimumJointConfidence else {
                return CGPoint(x: -1, y: -1)
            }
            confidenceTotal += point.confidence
            validJointCount += 1
            return CGPoint(x: point.location.x, y: 1 - point.location.y)
        }

        guard validJointCount >= minimumValidJoints,
              let center = bodyCenter(for: points) else { return nil }
        return Candidate(
            points: points,
            center: center,
            score: confidenceTotal / Float(validJointCount)
        )
    }

    private func makeTrack(from candidate: Candidate) -> Track {
        Track(
            points: candidate.points,
            center: candidate.center,
            velocity: .zero,
            missedFrames: 0
        )
    }

    private func updateTrack(at index: Int, with candidate: Candidate) {
        guard let previous = tracks[index] else {
            tracks[index] = makeTrack(from: candidate)
            return
        }

        let stabilizedPoints = zip(candidate.points, previous.points).map(stabilize)
        let stabilizedCenter = bodyCenter(for: stabilizedPoints) ?? candidate.center
        let measuredVelocity = CGVector(
            dx: stabilizedCenter.x - previous.center.x,
            dy: stabilizedCenter.y - previous.center.y
        )
        let velocity = CGVector(
            dx: previous.velocity.dx * 0.45 + measuredVelocity.dx * 0.55,
            dy: previous.velocity.dy * 0.45 + measuredVelocity.dy * 0.55
        )

        tracks[index] = Track(
            points: stabilizedPoints,
            center: stabilizedCenter,
            velocity: velocity,
            missedFrames: 0
        )
    }

    private func stabilize(current: CGPoint, previous: CGPoint) -> CGPoint {
        let currentValid = isValid(current)
        let previousValid = isValid(previous)
        if !currentValid { return previousValid ? previous : current }
        if !previousValid { return current }

        let movement = hypot(current.x - previous.x, current.y - previous.y)
        let alpha = min(max(0.34 + movement * 4.5, 0.34), 0.9)
        return CGPoint(
            x: previous.x + (current.x - previous.x) * alpha,
            y: previous.y + (current.y - previous.y) * alpha
        )
    }

    private func matchDistance(track index: Int, candidate: Candidate) -> CGFloat {
        guard let track = tracks[index] else { return .infinity }
        let predicted = CGPoint(
            x: track.center.x + track.velocity.dx,
            y: track.center.y + track.velocity.dy
        )
        return hypot(candidate.center.x - predicted.x, candidate.center.y - predicted.y)
    }

    private func bodyCenter(for points: [CGPoint]) -> CGPoint? {
        let torsoIndices = [5, 6, 11, 12]
        let torso = torsoIndices.compactMap { index -> CGPoint? in
            guard points.indices.contains(index), isValid(points[index]) else { return nil }
            return points[index]
        }
        let usable = torso.isEmpty ? points.filter(isValid) : torso
        guard !usable.isEmpty else { return nil }
        let sum = usable.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(usable.count), y: sum.y / CGFloat(usable.count))
    }

    private func visibleTracks() -> [[CGPoint]] {
        guard tracks.contains(where: { $0 != nil }) else { return [] }
        let emptyPose = Array(repeating: CGPoint(x: -1, y: -1), count: jointOrder.count)
        let lastActiveIndex = tracks.lastIndex(where: { $0 != nil }) ?? 0
        return tracks[0...lastActiveIndex].map { $0?.points ?? emptyPose }
    }

    private func isValid(_ point: CGPoint) -> Bool {
        point.x >= 0 && point.y >= 0 && point.x <= 1 && point.y <= 1
    }
}
