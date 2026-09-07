import SwiftUI
import Combine
import AVFoundation

/// Plays the reference and the attempt together — overlaid on one canvas, or
/// side by side, each over its own video where one exists.
///
/// Overlaid: the reference drives the clock; the attempt is warped onto it
/// beat-by-beat (or by duration when beats are missing), then anchored
/// hip-to-hip and scaled torso-to-torso each frame so the two bodies overlap
/// even when the dancers stood in different places at different distances
/// from the camera.
///
/// Side by side: each skeleton stays in its own frame, on top of its own video
/// when the phone has it. The student's joints are still graded against the
/// teacher, so red means the same thing in both views.
///
/// Under the scrubber sits an error timeline: where the strip goes red is where
/// the student drifted. Slow the replay down, tap a peak, and see exactly which
/// limb was off at that moment.
struct LessonOverlayView: View {
    let reference: DanceRecording
    let attempt: DanceRecording
    /// From the comparison result: the attempt reads better left/right flipped.
    let mirrored: Bool
    /// "You" for the student; a teacher watching a shared attempt sees "Student".
    var attemptLabel: String = "You"
    /// Videos, when this phone has them. A lesson file never carries the
    /// teacher's; the student's is kept only when the attempt was saved.
    var referenceVideoURL: URL? = nil
    var attemptVideoURL: URL? = nil

    @State private var playbackTime: Double = 0
    @State private var isPlaying = true
    @State private var lastTick: Date?
    @State private var timeline: AttemptTimeline?
    @State private var showTeacher = true
    @State private var showStudent = true
    @State private var sideBySide = false
    @State private var showVideo = true
    @State private var referencePlayer: AVPlayer?
    @State private var attemptPlayer: AVPlayer?
    /// Where each dancer is in their frame, over the whole recording — so the
    /// side-by-side panels can close in on the bodies instead of showing two
    /// small figures in a lot of black.
    @State private var referenceFocus: CGRect?
    @State private var attemptFocus: CGRect?
    @AppStorage("replayRate") private var rate: Double = 1
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()
    private let teacherColor = Color(red: 0.20, green: 0.95, blue: 0.92)

    private var duration: Double {
        max(reference.effectiveFrameTimes.last ?? 0, 0.1)
    }

    private var hasAnyVideo: Bool { referenceVideoURL != nil || attemptVideoURL != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !sideBySide {
                overlaidStage
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

                // Each skeleton is a switch: see the teacher alone, the student
                // alone, or both. Colours match what SkeletonOverlay draws.
                HStack(spacing: 10) {
                    skeletonToggle("Teacher", color: teacherColor, isOn: $showTeacher)
                    skeletonToggle(attemptLabel, color: .green, isOn: $showStudent)
                    Label("Fix", systemImage: "circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 6)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6), in: Capsule())

                // Overlaid or side by side — and, side by side, with the videos.
                HStack(spacing: 10) {
                    layoutToggle("Overlaid", systemImage: "figure.2", isOn: !sideBySide) { sideBySide = false }
                    layoutToggle("Side by side", systemImage: "rectangle.split.2x1", isOn: sideBySide) { sideBySide = true }
                    if sideBySide {
                        layoutToggle("Video", systemImage: showVideo ? "video.fill" : "video.slash", isOn: showVideo && hasAnyVideo) {
                            showVideo.toggle()
                        }
                        .disabled(!hasAnyVideo)
                        .opacity(hasAnyVideo ? 1 : 0.4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6), in: Capsule())
                .padding(.top, 8)

                if sideBySide {
                    sideBySideStage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, 10)
                } else {
                    Spacer()
                }

                controls
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
        .onAppear {
            timeline = AttemptTimeline.build(reference: reference, attempt: attempt, mirrored: mirrored)
            lastTick = Date()
            referencePlayer = referenceVideoURL.map(makePlayer)
            attemptPlayer = attemptVideoURL.map(makePlayer)
            referenceFocus = Self.focus(of: reference)
            attemptFocus = Self.focus(of: attempt)
        }
        .onDisappear {
            referencePlayer?.pause()
            attemptPlayer?.pause()
        }
        .onReceive(timer) { now in
            tick(now)
        }
    }

    // MARK: - Stages

    private var overlaidStage: some View {
        let refPose = PoseFeedback.interpolatedPose(of: reference, at: playbackTime)
        let attPose = attemptPose(at: playbackTime, alignedTo: refPose)
        return ZStack {
            if showTeacher, let refPose {
                SkeletonOverlay(keypoints: [refPose], videoAspect: 9.0 / 16.0)
                    .ignoresSafeArea()
            }
            if showStudent, let attPose {
                SkeletonOverlay(
                    keypoints: [attPose],
                    videoAspect: 9.0 / 16.0,
                    errorLevels: refPose.flatMap {
                        PoseFeedback.jointErrors(reference: $0, alignedAttempt: attPose)
                    }
                )
                .ignoresSafeArea()
            }
        }
    }

    /// Two portrait panels of exactly the same size, as large as the space
    /// allows. Over video, each skeleton is drawn in its own frame so it sits
    /// on its own body. Without video, the student is drawn at the teacher's
    /// size and place, so the two read at one scale. Colours always come from
    /// the aligned comparison, swapped back onto the right limbs when mirrored.
    private var sideBySideStage: some View {
        let refPose = PoseFeedback.interpolatedPose(of: reference, at: playbackTime)
        let attTime = PoseFeedback.attemptTime(forReferenceTime: playbackTime, reference: reference, attempt: attempt)
        let rawAttPose = PoseFeedback.interpolatedPose(of: attempt, at: attTime)
        let aligned = attemptPose(at: playbackTime, alignedTo: refPose)

        var errors: [Double]?
        if let refPose, let aligned {
            errors = PoseFeedback.jointErrors(reference: refPose, alignedAttempt: aligned)
        }
        let studentOverVideo = showVideo && attemptPlayer != nil
        let studentPose = studentOverVideo ? rawAttPose : aligned
        let studentErrors = (studentOverVideo && mirrored) ? errors.map(PoseFeedback.swapSides) : errors
        // Drawn in the teacher's frame when not over video, so framed like the teacher.
        let studentFocus = studentOverVideo ? attemptFocus : referenceFocus
        // One zoom for both, so the two bodies stay at one scale.
        let zoom = min(Self.zoom(for: referenceFocus), Self.zoom(for: studentFocus))

        return GeometryReader { geo in
            let gap: CGFloat = 4
            let width = min((geo.size.width - gap) / 2, geo.size.height * 9 / 16)
            let height = width * 16 / 9
            HStack(spacing: gap) {
                panel(pose: showTeacher ? refPose : nil, errors: nil, player: referencePlayer,
                      focus: referenceFocus, zoom: zoom, size: CGSize(width: width, height: height))
                panel(pose: showStudent ? studentPose : nil, errors: studentErrors, player: attemptPlayer,
                      focus: studentFocus, zoom: zoom, size: CGSize(width: width, height: height))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// One dancer's frame: video underneath when there is one, skeleton on
    /// top, the whole thing scaled and shifted so the body fills the panel.
    private func panel(pose: [CGPoint]?, errors: [Double]?, player: AVPlayer?,
                       focus: CGRect?, zoom: CGFloat, size: CGSize) -> some View {
        let centre = focus.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: 0.5, y: 0.5)
        return ZStack {
            Color.white.opacity(0.05)
            ZStack {
                if let player {
                    VideoSurface(player: player)
                        .opacity(showVideo ? 1 : 0)
                }
                if let pose {
                    SkeletonOverlay(keypoints: [pose], videoAspect: 9.0 / 16.0, errorLevels: errors)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(zoom)
            .offset(x: (0.5 - centre.x) * zoom * size.width,
                    y: (0.5 - centre.y) * zoom * size.height)

            if showVideo, player == nil {
                VStack {
                    Spacer()
                    Text("no video")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// The box the dancer moves within, over the whole recording, with room
    /// around it. Every third frame is plenty; a body doesn't leave the box
    /// between two of them.
    private static func focus(of recording: DanceRecording) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude, minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
        var seen = false
        for (index, frame) in recording.keypoints.enumerated() where index % 3 == 0 {
            for point in frame.first ?? [] where PoseFeedback.isValid(point) {
                minX = min(minX, point.x); maxX = max(maxX, point.x)
                minY = min(minY, point.y); maxY = max(maxY, point.y)
                seen = true
            }
        }
        guard seen, maxX > minX, maxY > minY else { return nil }
        let padX = (maxX - minX) * 0.15, padY = (maxY - minY) * 0.12
        return CGRect(x: max(0, minX - padX), y: max(0, minY - padY),
                      width: min(1, maxX + padX) - max(0, minX - padX),
                      height: min(1, maxY + padY) - max(0, minY - padY))
    }

    /// How far a frame can be enlarged before its dancer would be cut off.
    private static func zoom(for focus: CGRect?) -> CGFloat {
        guard let focus, focus.width > 0.05, focus.height > 0.05 else { return 1 }
        return min(2.6, max(1, min(1 / focus.width, 1 / focus.height)))
    }

    // MARK: - Controls

    private func skeletonToggle(_ title: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: isOn.wrappedValue ? "circle.fill" : "circle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn.wrappedValue ? color : .white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn.wrappedValue ? color.opacity(0.18) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) skeleton")
        .accessibilityValue(isOn.wrappedValue ? "shown" : "hidden")
    }

    private func layoutToggle(_ title: String, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isOn ? .orange : .white.opacity(0.45))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.orange.opacity(0.18) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            readouts

            if let timeline {
                ErrorTimelineStrip(
                    timeline: timeline,
                    currentTime: playbackTime,
                    onSeek: { seek(to: $0) },
                    onPeakTap: { seek(to: $0.time) }
                )
                .padding(.horizontal, 14) // line up with the slider's track, not its thumb
            }

            HStack(spacing: 12) {
                Slider(
                    value: $playbackTime,
                    in: 0...duration,
                    onEditingChanged: { editing in
                        if editing { isPlaying = false }
                    }
                )
                .tint(.orange)
                SpeedSlider(rate: $rate)
            }

            HStack(spacing: 30) {
                Button {
                    if let peak = timeline?.peak(before: playbackTime) { seek(to: peak.time) }
                } label: {
                    Image(systemName: "backward.end.alt.fill")
                        .font(.system(size: 26))
                }
                .disabled(timeline?.peak(before: playbackTime) == nil)
                .accessibilityLabel("Previous problem moment")

                Button {
                    playbackTime = 0
                    isPlaying = true
                } label: {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 40))
                }

                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 58))
                }

                Button {
                    if let peak = timeline?.peak(after: playbackTime) { seek(to: peak.time) }
                } label: {
                    Image(systemName: "forward.end.alt.fill")
                        .font(.system(size: 26))
                }
                .disabled(timeline?.peak(after: playbackTime) == nil)
                .accessibilityLabel("Next problem moment")
            }
            .foregroundColor(.white)
        }
    }

    private var readouts: some View {
        HStack {
            HStack(spacing: 6) {
                Text("\(formatted(playbackTime)) / \(formatted(duration))")
                if let count = LessonComparator.countLabel(forRefTime: playbackTime, reference: reference) {
                    Text("·")
                    Text("count \(count)")
                }
            }
            .foregroundColor(.white)

            Spacer()

            if let timeline, let peak = timeline.nearestPeak(to: playbackTime) ?? timeline.worstPeak {
                let count = peak.count.map { " · count \($0)" } ?? ""
                Text("worst at \(formatted(peak.time))\(count)")
                    .foregroundColor(.red.opacity(0.9))
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
    }

    // MARK: - Playback

    private func tick(_ now: Date) {
        defer { lastTick = now }
        if isPlaying, let lastTick {
            playbackTime += now.timeIntervalSince(lastTick) * rate
            if playbackTime >= duration { playbackTime = 0 } // loop for practice
        }
        syncVideos()
    }

    private func seek(to seconds: Double) {
        isPlaying = false
        playbackTime = min(max(0, seconds), duration)
    }

    /// Keeps each video on the replay's clock: playing at the replay's speed,
    /// paused when it pauses, and nudged whenever it drifts. The student's video
    /// follows the warped attempt time, so it stays under the student's skeleton.
    private func syncVideos() {
        let attTime = PoseFeedback.attemptTime(forReferenceTime: playbackTime, reference: reference, attempt: attempt)
        sync(referencePlayer, to: playbackTime)
        sync(attemptPlayer, to: attTime)
    }

    private func sync(_ player: AVPlayer?, to target: Double) {
        guard let player, sideBySide, showVideo else { player?.pause(); return }
        let current = player.currentTime().seconds
        let drift = current.isFinite ? abs(current - target) : .infinity
        let tolerance = isPlaying ? 0.15 : 0.04
        if drift > tolerance {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
        }
        if isPlaying {
            if player.rate != Float(rate) { player.rate = Float(rate) }
        } else if player.rate != 0 {
            player.pause()
        }
    }

    private func makePlayer(_ url: URL) -> AVPlayer {
        let player = AVPlayer(url: url)
        player.isMuted = true // the replay has one clock; two soundtracks would fight it
        player.actionAtItemEnd = .pause
        return player
    }

    /// The student's pose at a reference time, on the teacher's body: warped
    /// onto the attempt clock, flipped if the comparator read it mirrored, then
    /// hip-anchored and torso-scaled. Same transform the error timeline uses.
    private func attemptPose(at time: Double, alignedTo refPose: [CGPoint]?) -> [CGPoint]? {
        let attTime = PoseFeedback.attemptTime(forReferenceTime: time, reference: reference, attempt: attempt)
        guard var pose = PoseFeedback.interpolatedPose(of: attempt, at: attTime) else { return nil }
        if mirrored { pose = PoseFeedback.mirrored(pose) }
        return PoseFeedback.align(attempt: pose, to: refPose, mirrored: false)
    }

    // MARK: - Formatting

    private func formatted(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        return String(format: "%d:%04.1f", Int(clamped) / 60, clamped.truncatingRemainder(dividingBy: 60))
    }
}
