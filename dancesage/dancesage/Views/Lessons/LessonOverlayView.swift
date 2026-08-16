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

            let refPose = pose(of: reference, at: playbackTime)
            let attPose = pose(of: attempt, at: attemptTime(forReferenceTime: playbackTime))
                .map { PoseFeedback.align(attempt: $0, to: refPose, mirrored: mirrored) }

            if let refPose {
                SkeletonOverlay(keypoints: [refPose], videoAspect: 9.0 / 16.0)
                    .ignoresSafeArea()
            }
            if let attPose {
                SkeletonOverlay(
                    keypoints: [attPose],
                    videoAspect: 9.0 / 16.0,
                    errorLevels: refPose.flatMap {
                        PoseFeedback.jointErrors(reference: $0, alignedAttempt: attPose)
                    }
                )
                .ignoresSafeArea()
            }

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
                    Label("Good", systemImage: "circle.fill")
                        .foregroundColor(.green)
                    Label("Fix", systemImage: "circle.fill")
                        .foregroundColor(.red)
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

    // MARK: - Pose lookup

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

}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
