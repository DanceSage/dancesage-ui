import SwiftUI
import Combine

/// Plays the reference and the attempt as two skeletons on one canvas.
///
/// The reference drives the clock; the attempt is warped onto it beat-by-beat
/// (or by duration when beats are missing), then anchored hip-to-hip and scaled
/// torso-to-torso each frame so the two bodies overlap even when the dancers
/// stood in different places at different distances from the camera.
struct LessonOverlayView: View {
    let reference: DanceRecording
    let attempt: DanceRecording
    /// From the comparison result: the attempt reads better left/right flipped.
    let mirrored: Bool

    @State private var playbackTime: Double = 0
    @State private var isPlaying = true
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var duration: Double {
        max(reference.effectiveFrameTimes.last ?? 0, 0.1)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SkeletonOverlay(
                keypoints: overlaidPoses(at: playbackTime),
                videoAspect: 9.0 / 16.0
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .padding()
                    }
                    Spacer()
                }

                // Legend uses the same palette order SkeletonOverlay assigns.
                HStack(spacing: 18) {
                    Label("Teacher", systemImage: "circle.fill")
                        .foregroundColor(Color(red: 0.20, green: 0.95, blue: 0.92))
                    Label("You", systemImage: "circle.fill")
                        .foregroundColor(Color(red: 1.00, green: 0.78, blue: 0.18))
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.6), in: Capsule())

                Spacer()

                VStack(spacing: 14) {
                    Slider(
                        value: $playbackTime,
                        in: 0...duration,
                        onEditingChanged: { editing in
                            if editing { isPlaying = false }
                        }
                    )
                    .tint(.orange)

                    HStack(spacing: 34) {
                        Button {
                            playbackTime = 0
                            isPlaying = true
                        } label: {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                        }
                        Button {
                            isPlaying.toggle()
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 58))
                                .foregroundColor(.white)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
            }
        }
        .onReceive(timer) { _ in
            guard isPlaying else { return }
            playbackTime += 1.0 / 60.0
            if playbackTime >= duration { playbackTime = 0 } // loop for practice
        }
    }

    // MARK: - Pose assembly

    private func overlaidPoses(at time: Double) -> [[CGPoint]] {
        var poses: [[CGPoint]] = []
        let refPose = pose(of: reference, at: time)
        if let refPose { poses.append(refPose) }
        if let attPose = pose(of: attempt, at: attemptTime(forReferenceTime: time)) {
            let adjusted = align(attempt: attPose, to: refPose)
            poses.append(adjusted)
        }
        return poses
    }

    private func pose(of recording: DanceRecording, at seconds: Double) -> [CGPoint]? {
        let times = recording.effectiveFrameTimes
        guard !times.isEmpty else { return nil }
        var low = 0
        var high = times.count - 1
        if seconds > times[0] {
            while low < high {
                let middle = (low + high + 1) / 2
                if times[middle] <= seconds { low = middle } else { high = middle - 1 }
            }
        }
        return recording.keypoints[safe: low]?.first
    }

    /// Warps reference time onto the attempt's clock, beat interval by beat interval.
    private func attemptTime(forReferenceTime time: Double) -> Double {
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

    /// Mirrors (if needed), then anchors the attempt's hips onto the reference's hips
    /// and matches torso scale, so the comparison is about shape, not staging.
    private func align(attempt pose: [CGPoint], to referencePose: [CGPoint]?) -> [CGPoint] {
        var pose = pose
        if mirrored {
            pose = pose.map { $0.x >= 0 && $0.y >= 0 ? CGPoint(x: 1 - $0.x, y: $0.y) : $0 }
        }
        guard pose.count == 33, let refPose = referencePose, refPose.count == 33 else { return pose }

        func valid(_ p: CGPoint) -> Bool { p.x >= 0 && p.y >= 0 }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint? {
            guard valid(a), valid(b) else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x, dy = a.y - b.y
            return (dx * dx + dy * dy).squareRoot()
        }

        guard let refHips = mid(refPose[23], refPose[24]),
              let refShoulders = mid(refPose[11], refPose[12]),
              let attHips = mid(pose[23], pose[24]),
              let attShoulders = mid(pose[11], pose[12]) else { return pose }

        let refTorso = distance(refShoulders, refHips)
        let attTorso = distance(attShoulders, attHips)
        guard attTorso > 0.001, refTorso > 0.001 else { return pose }
        let scale = refTorso / attTorso

        return pose.map { point in
            guard valid(point) else { return point }
            return CGPoint(
                x: (point.x - attHips.x) * scale + refHips.x,
                y: (point.y - attHips.y) * scale + refHips.y
            )
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
