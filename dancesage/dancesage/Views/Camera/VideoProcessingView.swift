import SwiftUI

struct VideoProcessingView: View {
    @StateObject private var videoProcessor = VideoProcessor()
    @StateObject private var beatDetector = BeatDetector()
    let videoURL: URL
    var isPartnerMode: Bool = true  // true = show both dancers, false = show only first
    @Environment(\.dismiss) var dismiss
    @State private var showPlayback = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Processing Video")
                .font(.title)
                .bold()
            
            // Beat detection status
            if beatDetector.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Detecting beats...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else if beatDetector.bpm > 0 {
                VStack(spacing: 4) {
                    Text("🎵 \(Int(beatDetector.bpm)) BPM")
                        .font(.headline)
                        .foregroundColor(.purple)
                    Text("\(beatDetector.beats.count) beats detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if videoProcessor.isProcessing {
                ProgressView(value: videoProcessor.progress)
                    .progressViewStyle(.linear)
                    .frame(width: 300)
                
                Text("\(Int(videoProcessor.progress * 100))%")
                    .font(.headline)
            } else if !videoProcessor.keypoints.isEmpty {
                Text("✅ Processing Complete!")
                    .font(.headline)
                    .foregroundColor(.green)
                
                let totalPeople = videoProcessor.keypoints.flatMap { $0 }.count
                let avgPeoplePerFrame = totalPeople > 0 ? Double(totalPeople) / Double(videoProcessor.keypoints.count) : 0
                let modeText = isPartnerMode ? "Partner" : "Styling"
                
                Text("Detected \(videoProcessor.keypoints.count) frames")
                    .font(.subheadline)
                
                Text("Mode: \(modeText) | Avg \(String(format: "%.1f", avgPeoplePerFrame)) people/frame")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("View Skeleton") {
                    showPlayback = true
                }
                .buttonStyle(.borderedProminent)
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            } else {
                // Processing finished but no poses detected
                Text("⚠️ No poses detected")
                    .font(.headline)
                    .foregroundColor(.orange)
                
                Text("Try a video with a person clearly visible")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            videoProcessor.setPartnerMode(isPartnerMode)  // ADD THIS LINE
            videoProcessor.processVideo(url: videoURL)
            beatDetector.detectBeats(from: videoURL) { beats, bpm in
                print("🎵 BEATS: \(beats.prefix(8).map { String(format: "%.2f", $0) })")
            }
        }
        .fullScreenCover(isPresented: $showPlayback) {
            SkeletonPlaybackView(
                keypoints: filteredKeypoints,
                allowSave: true,
                beats: beatDetector.beats,
                bpm: beatDetector.bpm,
                videoURL: videoURL
            )
        }
    }
    
    // Filter keypoints based on mode
    private var filteredKeypoints: [[[CGPoint]]] {
        if isPartnerMode {
            // Partner mode: show all detected people
            return videoProcessor.keypoints
        } else {
            // Styling mode: show only the first person
            return videoProcessor.keypoints.map { frame in
                frame.isEmpty ? [] : [frame[0]]
            }
        }
    }
}
