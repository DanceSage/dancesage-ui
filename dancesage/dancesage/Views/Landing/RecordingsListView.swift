import SwiftUI

struct RecordingsListView: View {
    @State private var recordings: [DanceRecording] = []
    @State private var selectedRecording: DanceRecording?
    @State private var errorMessage = ""
    @State private var exportedVideo: ExportedVideo?
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                if recordings.isEmpty {
                    VStack {
                        Text("No recordings yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Start recording to save your dances")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        ForEach(recordings) { recording in
                            HStack {
                                Button(action: {
                                    selectedRecording = recording
                                }) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(recording.name)
                                            .font(.headline)
                                        HStack {
                                            Image(systemName: recording.hasVideo == true ? "video.fill" : "figure.walk")
                                                .foregroundColor(recording.hasVideo == true ? .blue : .secondary)
                                            Text("\(recording.frameCount) frames")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                            Spacer()
                                            Text(recording.timestamp, style: .date)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)

                                // Share menu: the original video, or the recording as a
                                // teachable lesson file. Skeleton exports live in playback,
                                // where the render options are.
                                Menu {
                                    if let videoURL = RecordingStore.shared.existingVideoURL(for: recording) {
                                        Button {
                                            exportedVideo = ExportedVideo(url: videoURL)
                                        } label: {
                                            Label("Share Video", systemImage: "video")
                                        }
                                    }
                                    Button {
                                        shareAsLesson(recording)
                                    } label: {
                                        Label("Share as Lesson", systemImage: "graduationcap")
                                    }
                                } label: {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 18))
                                        .foregroundColor(.blue)
                                        .padding(.leading, 12)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .onDelete(perform: deleteRecording)
                    }
                }
            }
            .navigationTitle("My Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadRecordings()
            }
            .fullScreenCover(item: $selectedRecording) { recording in
                SkeletonPlaybackView(
                    keypoints: recording.keypoints,
                    allowSave: false,
                    beats: recording.beats ?? [],
                    bpm: recording.bpm ?? 0,
                    fps: recording.effectiveFPS,
                    frameTimes: recording.effectiveFrameTimes,
                    recordingMode: recording.mode ?? .styling,
                    videoURL: RecordingStore.shared.existingVideoURL(for: recording),
                    cameraPosition: recording.cameraPosition
                )
            }
            .sheet(item: $exportedVideo) { export in
                ActivityView(url: export.url)
            }
            .alert("Recording Error", isPresented: Binding(
                get: { !errorMessage.isEmpty },
                set: { if !$0 { errorMessage = "" } }
            )) {
                Button("OK", role: .cancel) { errorMessage = "" }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    func loadRecordings() {
        do {
            recordings = try RecordingStore.shared.load()
        } catch {
            recordings = []
            errorMessage = error.localizedDescription
        }
    }
    
    func shareAsLesson(_ recording: DanceRecording) {
        do {
            let url = try LessonStore.shared.exportLessonFile(
                recording: recording,
                teacherName: UIDevice.current.name,
                note: ""
            )
            exportedVideo = ExportedVideo(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRecording(at offsets: IndexSet) {
        do {
            recordings = try RecordingStore.shared.delete(at: offsets)
            print("✅ Recording deleted")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
