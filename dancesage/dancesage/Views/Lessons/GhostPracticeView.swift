import SwiftUI
import Combine
import AVFoundation

/// Ghost practice: the teacher's skeleton plays over the live camera while the
/// student dances inside it. The student's live skeleton and the ghost render
/// together, the attempt is captured, and scoring runs the moment the ghost
/// finishes — practice by following, not by recording blind.
///
/// Deliberately separate from ContentView's recording flow so the core camera
/// path stays untouched. Solo (styling) lessons only for now.
struct GhostPracticeView: View {
    let lesson: Lesson

    @StateObject private var poseDetector = PoseDetector()
    @StateObject private var visionDetector = VisionPoseDetector()

    @State private var cameraPosition: AVCaptureDevice.Position = .front
    @State private var recordingRequested = false
    @State private var captureActive = false
    @State private var captureError = ""

    @State private var countdown: Int? = nil
    @State private var ghostTime: Double = 0
    @State private var ghostRunning = false
    @State private var resultBox: GhostResultBox?
    @State private var liveErrorLevels: [Double]?

    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var ghostDuration: Double {
        lesson.recording.effectiveFrameTimes.last ?? 0
    }

    private var isBusy: Bool { recordingRequested || captureActive || countdown != nil }

    var body: some View {
        ZStack {
            LiveCameraView(
                poseDetector: poseDetector,
                visionDetector: visionDetector,
                isPartnerMode: false,
                cameraPosition: cameraPosition,
                recordingRequested: recordingRequested,
                onRecordingStarted: ghostAndRecordingStarted,
                onRecordingFinished: recordingFinished,
                onError: { captureError = $0 }
            )
            .ignoresSafeArea()

            // Teacher ghost in the jewel palette; the student's skeleton is
            // graded live — green where matching the ghost, red where off.
            if let ghost = ghostPose() {
                SkeletonOverlay(keypoints: [ghost], useVisionIndices: false)
                    .ignoresSafeArea()
            }
            if let student = poseDetector.keypoints.first {
                SkeletonOverlay(
                    keypoints: [student],
                    useVisionIndices: false,
                    errorLevels: liveErrorLevels
                )
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button {
                        recordingRequested = false
                        ghostRunning = false
                        poseDetector.clearRecording()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                            .padding()
                    }
                    .disabled(captureActive)

                    Spacer()

                    Button(action: switchCamera) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .disabled(isBusy)

                    HStack(spacing: 14) {
                        Label("Teacher", systemImage: "circle.fill")
                            .foregroundColor(Color(red: 0.20, green: 0.95, blue: 0.92))
                        Label("Good", systemImage: "circle.fill")
                            .foregroundColor(.green)
                        Label("Fix", systemImage: "circle.fill")
                            .foregroundColor(.red)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(.trailing)
                }

                if ghostRunning, ghostDuration > 0 {
                    ProgressView(value: min(ghostTime / ghostDuration, 1))
                        .tint(Color(red: 0.20, green: 0.95, blue: 0.92))
                        .padding(.horizontal, 40)
                }

                Spacer()

                if let countdown {
                    Text("\(countdown)")
                        .font(.system(size: 130, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.6), radius: 12)
                        .transition(.scale)
                }

                Spacer()

                Button(action: startPractice) {
                    Text(isBusy ? "Dancing…" : "Dance With the Teacher")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(isBusy ? Color.gray.opacity(0.6) : Color.orange, in: Capsule())
                }
                .disabled(isBusy)
                .padding(.bottom, 46)
            }
        }
        .onAppear {
            poseDetector.setMode(numPoses: 1)
        }
        .onReceive(timer) { _ in
            tick()
        }
        .sheet(item: $resultBox) { box in
            ComparisonResultsView(
                result: box.result,
                lessonName: lesson.title,
                attemptName: "Ghost practice",
                reference: lesson.recording,
                attempt: box.attempt
            )
        }
        .alert("Camera Error", isPresented: Binding(
            get: { !captureError.isEmpty },
            set: { if !$0 { captureError = "" } }
        )) {
            Button("OK", role: .cancel) { captureError = "" }
        } message: {
            Text(captureError)
        }
    }

    // MARK: - Live grading

    /// Grades the student's live pose against the ghost: hip-anchored so where
    /// you stand doesn't count as error, both mirror orientations tried, a small
    /// reaction-lag window so following a third of a second behind isn't
    /// punished, and temporally smoothed so colors don't flicker.
    private func updateLiveErrors() {
        guard let student = poseDetector.keypoints.first, student.count == 33 else {
            liveErrorLevels = nil
            return
        }

        // Candidate ghost poses: now and slightly in the past (reaction lag).
        var ghostCandidates: [[CGPoint]] = []
        let currentTime = ghostTime
        for offset in [0.0, 0.2, 0.4] {
            if let pose = ghostPose(at: max(0, currentTime - offset)) {
                ghostCandidates.append(pose)
            }
            if !ghostRunning { break } // idle: only the opening pose exists
        }
        guard !ghostCandidates.isEmpty else {
            liveErrorLevels = nil
            return
        }

        let studentVariants = [student, PoseFeedback.mirrored(student)]

        var best: [Double]?
        var bestMean = Double.greatestFiniteMagnitude
        for ghost in ghostCandidates {
            for variant in studentVariants {
                let aligned = PoseFeedback.align(attempt: variant, to: ghost, mirrored: false)
                guard let errors = PoseFeedback.jointErrors(reference: ghost, alignedAttempt: aligned) else { continue }
                let mean = errors.reduce(0, +) / Double(errors.count)
                if mean < bestMean {
                    bestMean = mean
                    best = errors
                }
            }
        }
        guard let target = best else {
            liveErrorLevels = nil
            return
        }

        // Exponential smoothing keeps the colors readable rather than strobing.
        if let previous = liveErrorLevels, previous.count == target.count {
            liveErrorLevels = zip(previous, target).map { $0 * 0.7 + $1 * 0.3 }
        } else {
            liveErrorLevels = target
        }
    }

    /// The teacher's pose at the current ghost clock — or the opening pose while
    /// idle, so the student can find their starting position before the count.
    private func ghostPose() -> [CGPoint]? {
        ghostPose(at: ghostTime)
    }

    private func ghostPose(at time: Double) -> [CGPoint]? {
        let recording = lesson.recording
        guard let firstPose = recording.keypoints.first?.first else { return nil }
        guard ghostRunning else { return firstPose }

        let times = recording.effectiveFrameTimes
        var low = 0
        var high = times.count - 1
        if time > times[0] {
            while low < high {
                let middle = (low + high + 1) / 2
                if times[middle] <= time { low = middle } else { high = middle - 1 }
            }
        }
        return recording.keypoints.indices.contains(low) ? recording.keypoints[low].first : firstPose
    }

    // MARK: - Practice flow

    private func startPractice() {
        poseDetector.clearRecording()
        ghostTime = 0
        countdown = 3
        runCountdown()
    }

    private func runCountdown() {
        guard let current = countdown else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if current > 1 {
                countdown = current - 1
                runCountdown()
            } else {
                countdown = nil
                recordingRequested = true // capture start also starts the ghost
            }
        }
    }

    private func ghostAndRecordingStarted() {
        captureActive = true
        ghostTime = 0
        ghostRunning = true
        poseDetector.startRecording()
    }

    private func tick() {
        updateLiveErrors()
        guard ghostRunning else { return }
        ghostTime += 1.0 / 60.0
        if ghostTime >= ghostDuration {
            ghostRunning = false
            recordingRequested = false // capture teardown calls recordingFinished
        }
    }

    private func recordingFinished(_ url: URL) {
        recordingRequested = false
        captureActive = false
        ghostRunning = false
        poseDetector.stopRecording()
        // The practice video itself isn't kept — the attempt is the skeleton.
        try? FileManager.default.removeItem(at: url)

        let keypoints = poseDetector.recordedKeypoints
        let frameTimes = poseDetector.recordedFrameTimes
        guard keypoints.count >= 8 else {
            captureError = "Not enough of your dancing was captured. Keep your whole body in frame and try again."
            return
        }

        // The student danced on the ghost's clock, so the lesson's beats are the
        // attempt's beats — this makes the comparison exactly count-aligned.
        let attempt = DanceRecording(
            name: "Ghost practice",
            keypoints: keypoints,
            mode: .styling,
            fps: lesson.recording.effectiveFPS,
            frameTimes: frameTimes,
            beats: lesson.recording.beats ?? [],
            bpm: lesson.recording.bpm ?? 0,
            hasVideo: false,
            cameraPosition: cameraPosition == .front ? "front" : "back"
        )

        do {
            let result = try LessonComparator.compare(
                reference: lesson.recording,
                attempt: attempt
            )
            resultBox = GhostResultBox(result: result, attempt: attempt)
        } catch {
            captureError = error.localizedDescription
        }
    }

    private func switchCamera() {
        poseDetector.clearRecording()
        cameraPosition = cameraPosition == .back ? .front : .back
    }
}

private struct GhostResultBox: Identifiable {
    let result: LessonComparator.Result
    let attempt: DanceRecording
    let id = UUID()
}
