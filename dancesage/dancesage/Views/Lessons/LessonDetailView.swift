import SwiftUI

/// One lesson: watch the reference skeleton, then compare one of your recordings against it.
struct LessonDetailView: View {
    let lesson: Lesson

    @State private var showReference = false
    @State private var showGhostPractice = false
    @State private var showAttemptPicker = false
    @State private var resultBox: ComparisonResultBox?
    @State private var comparedAttempt: DanceRecording?
    @State private var errorMessage = ""
    @State private var attempts: [LessonAttempt] = []
    @State private var replayAttempt: LessonAttempt?
    @State private var postTarget: LessonAttempt?
    @State private var confirmRemove = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                if !lesson.teacherName.isEmpty {
                    LabeledContent("Teacher", value: lesson.teacherName)
                }
                LabeledContent("Frames", value: "\(lesson.recording.frameCount)")
                if let bpm = lesson.recording.bpm {
                    LabeledContent("Tempo", value: "\(Int(bpm)) BPM")
                }
                if !lesson.note.isEmpty {
                    Text(lesson.note)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                Button {
                    showReference = true
                } label: {
                    Label("Watch the Reference", systemImage: "play.circle.fill")
                }

                Button {
                    showGhostPractice = true
                } label: {
                    Label("Dance With the Teacher", systemImage: "figure.2")
                        .font(.body.weight(.semibold))
                }

                Button {
                    showAttemptPicker = true
                } label: {
                    Label("Compare a Saved Recording", systemImage: "figure.dance")
                }
            } footer: {
                Text("Dance With the Teacher shows the teacher's skeleton over your live camera — follow it, and you're scored the moment it ends. Or compare any recording you saved earlier.")
            }

            Section {
                if attempts.isEmpty {
                    Text("No attempts yet. Dance With the Teacher to record one.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(attempts) { attempt in
                        Button {
                            replayAttempt = attempt
                        } label: {
                            attemptRow(attempt)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !attempt.isPosted {
                                Button { postTarget = attempt } label: {
                                    Label("Save online", systemImage: "icloud.and.arrow.up")
                                }
                                .tint(.orange)
                            } else if attempt.sentToTeacher != true {
                                Button { Task { await send(attempt) } } label: {
                                    Label("Send to teacher", systemImage: "paperplane.fill")
                                }
                                .tint(.orange)
                            }
                        }
                        .contextMenu {
                            if !attempt.isPosted {
                                Button { postTarget = attempt } label: {
                                    Label("Save to my lessons online", systemImage: "icloud.and.arrow.up")
                                }
                            } else {
                                if attempt.sentToTeacher != true {
                                    Button { Task { await send(attempt) } } label: {
                                        Label("Send to teacher", systemImage: "paperplane.fill")
                                    }
                                }
                                // The online copy is replaced — for attempts saved before
                                // the web replay needed the video.
                                Button { Task { await replaceOnline(attempt) } } label: {
                                    Label("Re-upload with video", systemImage: "arrow.triangle.2.circlepath.icloud")
                                }
                            }
                        }
                    }
                    .onDelete(perform: deleteAttempts)
                }
            } header: {
                Text("Your attempts")
            } footer: {
                if !attempts.isEmpty {
                    Text("Tap one to watch both skeletons together. Swipe right to save it online, then to send it to your teacher — only a saved attempt can be sent.")
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label("Remove Lesson", systemImage: "trash")
                }
            } footer: {
                Text("Removes this lesson and every attempt at it — here and online. Your own recordings are not affected.")
            }
        }
        .confirmationDialog("Remove “\(lesson.title)”?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Lesson", role: .destructive) { removeLesson() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This lesson and \(attempts.count == 1 ? "its attempt" : "its \(attempts.count) attempts") are removed from this iPhone.")
        }
        .sheet(item: $postTarget) { attempt in
            PostRecordingView(
                keypoints: PoseFeedback.replayTrack(reference: lesson.recording, attempt: attempt.recording).keypoints,
                frameTimes: lesson.recording.effectiveFrameTimes,
                fps: lesson.recording.effectiveFPS,
                videoURL: RecordingStore.shared.existingVideoURL(for: attempt.recording),
                suggestedTitle: "\(lesson.title) — my attempt",
                replyTo: lesson.sourceVideoID,
                replyGroup: lesson.sourceGroupID.map { ($0, lesson.sourceGroupName ?? "the group") },
                        replyTeacher: lesson.teacherName.isEmpty ? nil : lesson.teacherName,
                replyMirrored: attempt.mirrored,
                replyAttemptTimes: PoseFeedback.replayTrack(reference: lesson.recording, attempt: attempt.recording).attemptTimes
            ) { id in
                var posted = attempt
                posted.postedVideoID = id
                if let list = try? LessonAttemptStore.shared.upsert(posted) { attempts = list }
            }
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadAttempts)
        .onChange(of: showGhostPractice) { _, showing in
            if !showing { loadAttempts() }
        }
        .fullScreenCover(item: $replayAttempt) { attempt in
            LessonOverlayView(
                reference: lesson.recording,
                attempt: attempt.recording,
                mirrored: attempt.mirrored,
                referenceVideoURL: RecordingStore.shared.existingVideoURL(for: lesson.recording),
                attemptVideoURL: RecordingStore.shared.existingVideoURL(for: attempt.recording)
            )
        }
        .fullScreenCover(isPresented: $showReference) {
            // The lesson's video too, when this phone has it — a lesson made from
            // a shared post brought it down; one that arrived as a file did not.
            SkeletonPlaybackView(
                keypoints: lesson.recording.keypoints,
                allowSave: false,
                beats: lesson.recording.beats ?? [],
                bpm: lesson.recording.bpm ?? 0,
                fps: lesson.recording.effectiveFPS,
                frameTimes: lesson.recording.effectiveFrameTimes,
                recordingMode: lesson.recording.mode ?? .styling,
                videoURL: RecordingStore.shared.existingVideoURL(for: lesson.recording)
            )
        }
        .fullScreenCover(isPresented: $showGhostPractice) {
            GhostPracticeView(lesson: lesson)
        }
        .sheet(isPresented: $showAttemptPicker) {
            AttemptPickerView { attempt in
                showAttemptPicker = false
                runComparison(attempt: attempt)
            }
        }
        .sheet(item: $resultBox) { box in
            if let comparedAttempt {
                ComparisonResultsView(
                    result: box.result,
                    lessonName: lesson.title,
                    attemptName: comparedAttempt.name,
                    reference: lesson.recording,
                    attempt: comparedAttempt,
                    lesson: lesson,
                    candidate: box.candidate,
                    referenceVideoURL: RecordingStore.shared.existingVideoURL(for: lesson.recording)
                )
            }
        }
        .onChange(of: resultBox?.id) { _, box in
            if box == nil { loadAttempts() } // the sheet may have saved one
        }
        .alert("Could Not Compare", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK", role: .cancel) { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    private func runComparison(attempt: DanceRecording) {
        do {
            let result = try LessonComparator.compare(
                reference: lesson.recording,
                attempt: attempt
            )
            comparedAttempt = attempt
            resultBox = ComparisonResultBox(
                result: result,
                candidate: LessonAttempt(lessonID: lesson.id, recording: attempt, result: result)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Attempts

    private func attemptRow(_ attempt: LessonAttempt) -> some View {
        HStack(spacing: 14) {
            Text("\(attempt.score)")
                .font(.headline.monospacedDigit())
                .foregroundColor(scoreColor(attempt.score))
                .frame(width: 44, height: 44)
                .background(scoreColor(attempt.score).opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(attempt.createdAt, format: .dateTime.month().day().hour().minute())
                    .font(.body)
                    .foregroundColor(.primary)

                HStack(spacing: 8) {
                    Text(attempt.recording.name)
                    if attempt.mirrored {
                        Label("Mirrored", systemImage: "arrow.left.and.right")
                    }
                    if attempt.sentToTeacher == true {
                        Label("Sent to teacher", systemImage: "paperplane.fill")
                    } else if attempt.isPosted {
                        Label("Saved online", systemImage: "icloud.fill")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            }

            Spacer()

            Image(systemName: "play.circle")
                .foregroundColor(.secondary)
        }
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...: return .green
        case 55..<80: return .yellow
        default: return .orange
        }
    }

    /// Here and online, with every attempt — the two are one lesson.
    private func removeLesson() {
        do {
            try LessonStore.shared.delete(id: lesson.id)
            if let online = lesson.onlineLessonID {
                Task { try? await DanceSagePlatform.shared.deleteLesson(id: online) }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadAttempts() {
        do {
            attempts = try LessonAttemptStore.shared.attempts(forLesson: lesson.id)
        } catch {
            attempts = []
            errorMessage = error.localizedDescription
        }
        Task { await syncSent() }
    }

    /// Sending can happen from the web too; ask which attempts have gone.
    private func syncSent() async {
        guard attempts.contains(where: { $0.isPosted && $0.sentToTeacher != true }),
              let sent = try? await DanceSagePlatform.shared.sentAttempts() else { return }
        var changed = false
        for a in attempts where a.postedVideoID.map(sent.contains) == true && a.sentToTeacher != true {
            var updated = a; updated.sentToTeacher = true
            if (try? LessonAttemptStore.shared.upsert(updated)) != nil { changed = true }
        }
        if changed, let fresh = try? LessonAttemptStore.shared.attempts(forLesson: lesson.id) { attempts = fresh }
    }

    /// Drops the online copy and posts this attempt again in the current shape.
    private func replaceOnline(_ attempt: LessonAttempt) async {
        if let id = attempt.postedVideoID {
            try? await DanceSagePlatform.shared.deleteVideo(id: id)
        }
        var fresh = attempt
        fresh.postedVideoID = nil
        fresh.sentToTeacher = nil
        if let list = try? LessonAttemptStore.shared.upsert(fresh) { attempts = list }
        postTarget = fresh
    }

    private func send(_ attempt: LessonAttempt) async {
        guard let id = attempt.postedVideoID else { return }
        do {
            try await DanceSagePlatform.shared.sendAttempt(id: id)
            var updated = attempt; updated.sentToTeacher = true
            attempts = try LessonAttemptStore.shared.upsert(updated)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAttempts(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where attempts.indices.contains(index) {
            do {
                if let online = attempts[index].postedVideoID {
                    Task { try? await DanceSagePlatform.shared.deleteAttempt(videoID: online) }
                }
                attempts = try LessonAttemptStore.shared.delete(id: attempts[index].id, lessonID: lesson.id)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
    }
}

/// Identifiable wrapper so a comparison result can drive a sheet.
private struct ComparisonResultBox: Identifiable {
    let result: LessonComparator.Result
    let candidate: LessonAttempt
    let id = UUID()
}

/// Picks one of the dancer's saved recordings as the attempt.
private struct AttemptPickerView: View {
    let onPick: (DanceRecording) -> Void

    @State private var recordings: [DanceRecording] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Group {
                if recordings.isEmpty {
                    VStack(spacing: 8) {
                        Text("No recordings yet")
                            .font(.title3.weight(.semibold))
                        Text("Record yourself dancing the move first, then come back and compare.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                } else {
                    List(recordings) { recording in
                        Button {
                            onPick(recording)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recording.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                HStack {
                                    Text("\(recording.frameCount) frames")
                                    Spacer()
                                    Text(recording.timestamp, style: .date)
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick Your Attempt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                recordings = (try? RecordingStore.shared.load())?
                    .sorted { $0.timestamp > $1.timestamp } ?? []
            }
        }
    }
}
