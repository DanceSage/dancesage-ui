import SwiftUI

struct VideoProcessingView: View {
    @StateObject private var videoProcessor = VideoProcessor()
    @StateObject private var beatDetector = BeatDetector()
    let videoURL: URL
    var isPartnerMode: Bool = true  // true = show both dancers, false = show only first
    @State private var hasStarted = false
    
    var body: some View {
        SkeletonPlaybackView(
            keypoints: filteredKeypoints,
            allowSave: true,
            beats: beatDetector.beats,
            bpm: beatDetector.bpm,
            fps: 15,
            frameTimes: videoProcessor.frameTimes,
            recordingMode: isPartnerMode ? .partner : .styling,
            videoURL: videoURL,
            isProcessing: videoProcessor.isProcessing,
            processingProgress: videoProcessor.progress,
            worldKeypoints: videoProcessor.worldKeypoints
        )
        .onAppear {
            guard !hasStarted else { return }
            hasStarted = true
            videoProcessor.setPartnerMode(isPartnerMode)
            videoProcessor.processVideo(url: videoURL)
            beatDetector.detectBeats(from: videoURL) { beats, bpm in
                print("🎵 BEATS: \(beats.prefix(8).map { String(format: "%.2f", $0) })")
            }
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
