import SwiftUI

struct RecordingsListView: View {
    @State private var recordings: [DanceRecording] = []
    @State private var selectedRecording: DanceRecording?
    @State private var showPlayback = false
    @State private var errorMessage = ""
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
                            Button(action: {
                                selectedRecording = recording
                                showPlayback = true
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
            .fullScreenCover(isPresented: $showPlayback) {
                if let recording = selectedRecording {
                    SkeletonPlaybackView(
                        keypoints: recording.keypoints,
                        allowSave: false,
                        beats: recording.beats ?? [],
                        bpm: recording.bpm ?? 0,
                        fps: recording.effectiveFPS,
                        frameTimes: recording.effectiveFrameTimes,
                        recordingMode: recording.mode ?? .styling,
                        videoURL: recording.hasVideo == true ? RecordingStore.shared.videoURL(for: recording) : nil,
                        cameraPosition: recording.cameraPosition
                    )
                }
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
    
    func deleteRecording(at offsets: IndexSet) {
        do {
            recordings = try RecordingStore.shared.delete(at: offsets)
            print("✅ Recording deleted")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
