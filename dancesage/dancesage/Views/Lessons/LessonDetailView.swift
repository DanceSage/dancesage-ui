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
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showReference) {
            SkeletonPlaybackView(
                keypoints: lesson.recording.keypoints,
                allowSave: false,
                beats: lesson.recording.beats ?? [],
                bpm: lesson.recording.bpm ?? 0,
                fps: lesson.recording.effectiveFPS,
                frameTimes: lesson.recording.effectiveFrameTimes,
                recordingMode: lesson.recording.mode ?? .styling
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
                    attempt: comparedAttempt
                )
            }
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
            comparedAttempt = attempt
            resultBox = ComparisonResultBox(
                result: try LessonComparator.compare(
                    reference: lesson.recording,
                    attempt: attempt
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Identifiable wrapper so a comparison result can drive a sheet.
private struct ComparisonResultBox: Identifiable {
    let result: LessonComparator.Result
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
