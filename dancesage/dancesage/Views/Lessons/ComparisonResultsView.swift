import SwiftUI

/// The verdict: an overall score, per-region breakdown, and the spoken cues.
struct ComparisonResultsView: View {
    let result: LessonComparator.Result
    let lessonName: String
    let attemptName: String
    let reference: DanceRecording
    let attempt: DanceRecording
    /// The attempt as it would be saved. Nothing is kept until the student
    /// taps Save; sending is only possible after that.
    var lesson: Lesson? = nil
    var candidate: LessonAttempt? = nil
    /// A fresh capture waiting on the student's decision: moved into place on
    /// Save, deleted if the sheet closes without one.
    var pendingVideoURL: URL? = nil
    var referenceVideoURL: URL? = nil

    @State private var showOverlay = false
    @State private var coachText: String?
    @State private var saved: LessonAttempt?
    @State private var saveError = ""
    @State private var saving = false
    @State private var postedID: Int?
    @State private var sendNow = true
    @State private var sentTo: String?
    @StateObject private var publisher = DanceSagePublisher()
    @Environment(\.dismiss) private var dismiss

    private func speakFeedback() {
        if let coachText {
            CoachVoice.shared.speak(score: result.overallScore, cues: [coachText])
        } else {
            CoachVoice.shared.speak(score: result.overallScore, cues: result.cues)
        }
    }

    private var scoreColor: Color {
        switch result.overallScore {
        case 80...: return .green
        case 55..<80: return .yellow
        default: return .orange
        }
    }

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(spacing: 10) {
                        Text("\(result.overallScore)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundColor(scoreColor)
                        Text("\(attemptName) vs \(lessonName)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Label(
                                result.alignedByBeats ? "Compared on the beat" : "Compared over time",
                                systemImage: result.alignedByBeats ? "metronome" : "clock"
                            )
                            if result.mirrored {
                                Label("Mirrored view", systemImage: "arrow.left.and.right")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        // The measurements behind the number, so a strict score
                        // reads as a fact rather than a mood.
                        HStack(spacing: 12) {
                            Label(String(format: "typically %.0f° off", result.typicalDeviation), systemImage: "angle")
                            if result.meanLagSeconds >= 0.05 {
                                Label(String(format: "%.1f s behind", result.meanLagSeconds), systemImage: "hourglass")
                            }
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                Section {
                    Button {
                        CoachVoice.shared.stop()
                        showOverlay = true
                    } label: {
                        Label("Watch Them Together", systemImage: "figure.2")
                            .font(.body.weight(.semibold))
                    }
                } footer: {
                    Text("Both skeletons on one screen. Scrub, slow it down, and jump to your worst moments.")
                }

                if let lesson, candidate != nil {
                    Section {
                        if saved == nil {
                            Toggle(isOn: $sendNow) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send to \(lesson.teacherName.isEmpty ? "the teacher" : lesson.teacherName) now")
                                    Text("Off, it waits under My lessons — send it later from the lesson, or from the web.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button {
                                Task { await save(lesson: lesson) }
                            } label: {
                                HStack {
                                    Label("Save attempt", systemImage: "square.and.arrow.down")
                                        .font(.body.weight(.semibold))
                                    if saving { Spacer(); ProgressView() }
                                }
                            }
                            .disabled(saving)
                        } else {
                            Label(postedID == nil ? "Saved on this iPhone" : "Saved — here and under My lessons",
                                  systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            if let sentTo {
                                Label("Sent to \(sentTo)", systemImage: "paperplane.fill").foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Your attempt")
                    } footer: {
                        if !saveError.isEmpty {
                            Text(saveError).foregroundColor(.red)
                        } else if saved == nil {
                            Text("Nothing is kept unless you save. Saving keeps it here and under this lesson online — private, never on your profile.")
                        } else if postedID == nil {
                            Text("It's on this iPhone; the upload didn't go through. Long-press it on the lesson screen to try again.")
                        }
                    }
                }

                Section("What to work on") {
                    if let coachText {
                        Text(coachText)
                            .font(.body)
                    } else {
                        ForEach(Array(result.cues.enumerated()), id: \.offset) { _, cue in
                            Label(cue, systemImage: "speaker.wave.2.fill")
                                .font(.body)
                        }
                    }
                    Button {
                        speakFeedback()
                    } label: {
                        Label("Say It Again", systemImage: "arrow.clockwise")
                    }
                }

                Section("By body region") {
                    ForEach(result.regions) { region in
                        HStack {
                            Text(region.region.rawValue)
                            Spacer()
                            if let count = region.worstCount, region.meanDeviation > 12 {
                                Text("count \(count)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text("\(region.score)")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(region.score >= 80 ? .green : (region.score >= 55 ? .yellow : .orange))
                        }
                    }
                }

                Section {
                    Text("Based on \(result.samplesCompared) compared moments. Angles the camera couldn't see were skipped, never judged.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Your Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        CoachVoice.shared.stop()
                        dismiss()
                    }
                }
            }
            .task {
                // Prefer the on-device model's natural phrasing; fall back to
                // the measured cues where it's unavailable.
                coachText = await CoachBrain.naturalFeedback(
                    for: result,
                    lessonName: lessonName
                )
                speakFeedback()
            }
            .onDisappear {
                CoachVoice.shared.stop()
                if saved == nil, let pendingVideoURL {
                    try? FileManager.default.removeItem(at: pendingVideoURL)
                }
            }
            .fullScreenCover(isPresented: $showOverlay) {
                LessonOverlayView(
                    reference: reference,
                    attempt: attempt,
                    mirrored: result.mirrored,
                    referenceVideoURL: referenceVideoURL,
                    attemptVideoURL: attemptVideoURL
                )
            }
        }
    }

    /// Where the student's video is right now: still pending, or already in
    /// the library (a saved attempt, or a recording compared from the shelf).
    private var attemptVideoURL: URL? {
        if saved == nil, let pendingVideoURL { return pendingVideoURL }
        return RecordingStore.shared.existingVideoURL(for: attempt)
    }

    /// One save: on the phone (with the camera video), then under the lesson
    /// online, then — if asked — to the teacher. Each step reports its own
    /// failure; an earlier success is never undone by a later miss.
    private func save(lesson: Lesson) async {
        guard let candidate, saved == nil else { return }
        saving = true; saveError = ""
        defer { saving = false }
        do {
            if let pendingVideoURL {
                let home = RecordingStore.shared.videoURL(for: candidate.recording)
                try FileManager.default.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: home)
                try FileManager.default.moveItem(at: pendingVideoURL, to: home)
            }
            try LessonAttemptStore.shared.add(candidate)
            saved = candidate
        } catch {
            saveError = "Couldn't save: \(error.localizedDescription)"
            return
        }

        let track = PoseFeedback.replayTrack(reference: lesson.recording, attempt: candidate.recording)
        await publisher.publish(title: "\(lesson.title) — my attempt",
                                visibility: "private",
                                keypoints: track.keypoints,
                                frameTimes: lesson.recording.effectiveFrameTimes,
                                fps: lesson.recording.effectiveFPS,
                                videoURL: RecordingStore.shared.existingVideoURL(for: candidate.recording),
                                replyTo: lesson.sourceVideoID,
                                mirrored: candidate.mirrored,
                                attemptTimes: track.attemptTimes)
        if case .failed(let message) = publisher.stage {
            saveError = "Saved here, but not online: \(message)"
            return
        }
        guard let id = publisher.lastPublishedID else { return }
        postedID = id
        var online = candidate
        online.postedVideoID = id
        if sendNow {
            do {
                try await DanceSagePlatform.shared.sendAttempt(id: id)
                online.sentToTeacher = true
                sentTo = lesson.teacherName.isEmpty ? "the teacher" : lesson.teacherName
            } catch {
                saveError = "Saved, but could not send it: \(error.localizedDescription)"
            }
        }
        try? LessonAttemptStore.shared.upsert(online)
        saved = online
    }
}
