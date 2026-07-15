import SwiftUI
import Combine
import AVFoundation

private enum PlaybackDisplayMode: String, CaseIterable, Identifiable {
    case video = "Video"
    case skeleton = "Skeleton"
    case both = "Both"
    case threeD = "3D"

    var id: Self { self }
}

private struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

struct SkeletonPlaybackView: View {
    let keypoints: [[[CGPoint]]]
    let allowSave: Bool  // New parameter to control if save button shows
    var useVisionIndices: Bool = false  // For Vision vs MediaPipe joint mapping
    var beats: [Double] = []  // Beat timestamps in seconds
    var bpm: Double = 0
    var fps: Double = 15
    var frameTimes: [Double] = []
    var recordingMode: DanceRecording.Mode = .styling
    var videoURL: URL? = nil
    var cameraPosition: String? = nil
    var isProcessing: Bool = false
    var processingProgress: Double = 1
    var worldKeypoints: [[[PosePoint3D]]] = []
    
    @State private var currentFrame = 0
    @State private var isPlaying = false
    @State private var showSaveDialog = false
    @State private var recordingName = ""
    @State private var audioPlayer: AVPlayer? = nil
    @State private var playbackStartedAt: Date?
    @State private var playbackStartTime: Double = 0
    @State private var saveError = ""
    @State private var saveResultMessage = ""
    @State private var isSaving = false
    @State private var displayMode: PlaybackDisplayMode = .both
    @State private var videoAspect: CGFloat = 9.0 / 16.0
    @State private var videoDuration: Double = 0
    @State private var playbackTime: Double = 0
    @Environment(\.dismiss) var dismiss
    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var effectiveFPS: Double { max(fps, 1) }
    private var effectiveFrameTimes: [Double] {
        frameTimes.count == keypoints.count
            ? frameTimes
            : keypoints.indices.map { Double($0) / effectiveFPS }
    }

    private var duration: Double {
        if videoDuration > 0 { return videoDuration }
        return (effectiveFrameTimes.last ?? 0) + (1 / effectiveFPS)
    }

    private var chromeColor: Color {
        displayMode == .skeleton ? .black : .white
    }

    private var has3DFrames: Bool {
        worldKeypoints.count == keypoints.count && worldKeypoints.contains { frame in
            frame.contains { $0.count == 33 }
        }
    }

    private var currentWorldPoses: [[PosePoint3D]] {
        guard worldKeypoints.indices.contains(currentFrame) else { return [] }
        return worldKeypoints[currentFrame]
    }
    
    // Calculate current time from frame number
    var currentTime: Double {
        if videoURL != nil { return playbackTime }
        guard effectiveFrameTimes.indices.contains(currentFrame) else { return 0 }
        return effectiveFrameTimes[currentFrame]
    }

    private var skeletonIsAvailable: Bool {
        guard !keypoints.isEmpty, currentFrame < keypoints.count else { return false }
        guard isProcessing, let latestTime = effectiveFrameTimes.last else { return true }
        return playbackTime <= latestTime + 0.2
    }
    
    // Find which beat we're on (1-8 in the salsa count)
    var beatNumber: Int {
        guard !beats.isEmpty else { return 0 }
        
        // Find how many beats have passed
        let beatsPasssed = beats.filter { $0 <= currentTime }.count
        
        // Salsa counts 1-8, then repeats
        return beatsPasssed > 0 ? ((beatsPasssed - 1) % 8) + 1 : 0
    }
    
    // Check if we just hit a beat
    var isOnBeat: Bool {
        guard !beats.isEmpty else { return false }
        
        let tolerance = 0.05  // 50ms tolerance
        return beats.contains { abs($0 - currentTime) < tolerance }
    }
    
    var body: some View {
        ZStack {
            (displayMode == .skeleton ? Color.white : Color.black)
                .ignoresSafeArea()

            if displayMode == .video || displayMode == .both, let audioPlayer {
                VideoSurface(player: audioPlayer)
                    .ignoresSafeArea()
            }

            if displayMode == .skeleton || displayMode == .both, skeletonIsAvailable {
                SkeletonOverlay(
                    keypoints: keypoints[currentFrame],
                    useVisionIndices: useVisionIndices,
                    videoAspect: videoAspect
                )
                .ignoresSafeArea()
            }

            if displayMode == .threeD {
                Pose3DView(poses: currentWorldPoses)
                    .ignoresSafeArea()
            }

            if (displayMode == .skeleton || displayMode == .both), isProcessing, !skeletonIsAvailable {
                Text("Skeleton buffering…")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(chromeColor)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(
                        displayMode == .skeleton ? Color.white.opacity(0.9) : Color.black.opacity(0.72),
                        in: Capsule()
                    )
            }
            
            // Top bar: X button (left), Save button (right)
            VStack {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(chromeColor)
                            .padding()
                    }
                    
                    Spacer()
                    
                    // Save button (only show if allowSave is true)
                    if allowSave {
                        Button(action: {
                            showSaveDialog = true
                        }) {
                            Image(systemName: "square.and.arrow.down.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                                .padding()
                        }
                        .disabled(isSaving || isProcessing)
                    }
                }

                if videoURL != nil {
                    HStack(spacing: 8) {
                        ForEach(PlaybackDisplayMode.allCases) { mode in
                            Button {
                                if mode != .threeD || has3DFrames {
                                    displayMode = mode
                                }
                            } label: {
                                Text(mode.rawValue)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        displayMode == mode ? Color.blue : Color.black.opacity(0.78),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(.white.opacity(0.8), lineWidth: 1)
                                    }
                            }
                            .disabled(mode == .threeD && !has3DFrames)
                            .opacity(mode == .threeD && !has3DFrames ? 0.38 : 1)
                        }
                    }
                    .padding(.horizontal, 48)
                }

                if isProcessing {
                    VStack(spacing: 5) {
                        ProgressView(value: processingProgress)
                            .tint(.blue)
                        Text("Processing skeleton \(Int(processingProgress * 100))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(chromeColor)
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 8)
                }

                if displayMode == .threeD {
                    Label("Drag to rotate • Pinch to zoom", systemImage: "rotate.3d")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.58), in: Capsule())
                        .padding(.top, 8)
                }
                
                Spacer()
            }
            
            // Left side: Beat counter + 8-count dots (vertical, under X button)
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Spacer()
                        .frame(height: 60)  // Space for X button
                    
                    // Beat counter
                    if !beats.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Beat")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(beatNumber)")
                                .font(.system(size: 48, weight: .bold, design: .rounded))
                                .foregroundColor(.yellow)
                            if bpm > 0 {
                                Text("\(Int(bpm)) BPM")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                            }
                        }
                        
                        // 8-count dots (vertical)
                        VStack(spacing: 6) {
                            ForEach(1...8, id: \.self) { beat in
                                Circle()
                                    .fill(beat == beatNumber ? Color.yellow : Color.gray.opacity(0.5))
                                    .frame(width: beat == beatNumber ? 14 : 8, height: beat == beatNumber ? 14 : 8)
                                    .animation(.easeInOut(duration: 0.1), value: beatNumber)
                            }
                        }
                        .padding(.top, 8)
                    }
                    
                    Spacer()
                }
                .padding(.leading)
                
                Spacer()
            }
            
            // Bottom left: Frame counter
            VStack {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Frame")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(keypoints.isEmpty ? "0" : "\(currentFrame + 1)")
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(chromeColor)
                        Text("/ \(keypoints.count)")
                            .font(.caption)
                            .foregroundColor(.gray)
                        
                        Text(String(format: "%.2fs", currentTime))
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 2)
                    }
                    .padding()
                    
                    Spacer()
                }
            }
            
            // Bottom right: Play/Reset buttons (vertical)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        Button(action: {
                            togglePlayback()
                        }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(chromeColor)
                        }
                        
                        Button(action: {
                            resetPlayback()
                        }) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(chromeColor)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 40)
                }
            }
            
        }
        .onAppear {
            setupAudioPlayer()
            loadVideoAspect()
            if videoURL == nil { displayMode = .skeleton }
        }
        .onDisappear {
            audioPlayer?.pause()
            audioPlayer = nil
        }
        .onReceive(timer) { _ in
            updatePlaybackPosition()
        }
        .alert("Save Recording", isPresented: $showSaveDialog) {
            TextField("Dance name", text: $recordingName)
            Button("Save") {
                saveRecording()
            }
            Button("Cancel", role: .cancel) {
                recordingName = ""
            }
        } message: {
            Text("Enter a name for this dance recording")
        }
        .alert("Could Not Save", isPresented: Binding(
            get: { !saveError.isEmpty },
            set: { if !$0 { saveError = "" } }
        )) {
            Button("OK", role: .cancel) { saveError = "" }
        } message: {
            Text(saveError)
        }
        .alert("Recording Saved", isPresented: Binding(
            get: { !saveResultMessage.isEmpty },
            set: { if !$0 { saveResultMessage = "" } }
        )) {
            Button("Done") { dismiss() }
        } message: {
            Text(saveResultMessage)
        }
    }
    
    func saveRecording() {
        guard !recordingName.isEmpty else { return }
        
        guard !keypoints.isEmpty else {
            saveError = "This recording does not contain any frames."
            return
        }

        let recording = DanceRecording(
            name: recordingName,
            keypoints: keypoints,
            mode: recordingMode,
            fps: effectiveFPS,
            frameTimes: effectiveFrameTimes,
            beats: beats,
            bpm: bpm,
            hasVideo: videoURL != nil,
            cameraPosition: cameraPosition,
            worldKeypoints: worldKeypoints
        )
        
        // Save locally
        do {
            isSaving = true
            try RecordingStore.shared.append(recording, videoSourceURL: videoURL)
            print("✅ Saved recording locally: \(recordingName)")
        } catch {
            isSaving = false
            saveError = error.localizedDescription
            return
        }
        
        saveResultMessage = "Saved on this iPhone."
        isSaving = false
        recordingName = ""
    }
    
    // MARK: - Video Playback
    
    func setupAudioPlayer() {
        guard let url = videoURL else {
            return
        }
        
        // Configure audio session for playback
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("🔊 Audio session configured")
        } catch {
            print("❌ Audio session error: \(error)")
        }
        
        audioPlayer = AVPlayer(url: url)
        audioPlayer?.volume = 1.0
        print("🎬 Video player ready for: \(url.lastPathComponent)")
    }

    func loadVideoAspect() {
        guard let videoURL else { return }
        Task {
            let asset = AVURLAsset(url: videoURL)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let size = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform) else { return }
            let transformed = size.applying(transform)
            let width = abs(transformed.width)
            let height = abs(transformed.height)
            guard width > 0, height > 0 else { return }
            let loadedDuration = try? await asset.load(.duration)
            let duration = loadedDuration?.seconds
            await MainActor.run {
                videoAspect = width / height
                if let duration, duration.isFinite { videoDuration = duration }
            }
        }
    }
    
    func togglePlayback() {
        guard videoURL != nil || !keypoints.isEmpty else { return }
        isPlaying.toggle()
        
        if isPlaying {
            playbackStartTime = currentTime
            playbackStartedAt = Date()
            // Sync audio to current frame position
            let targetTime = CMTime(seconds: currentTime, preferredTimescale: 600)
            audioPlayer?.seek(to: targetTime) { _ in
                self.audioPlayer?.play()
            }
        } else {
            playbackStartedAt = nil
            audioPlayer?.pause()
        }
    }

    func updatePlaybackPosition() {
        guard isPlaying else { return }

        let elapsed: Double
        if let audioPlayer, audioPlayer.timeControlStatus == .playing {
            elapsed = audioPlayer.currentTime().seconds
        } else if let playbackStartedAt {
            elapsed = playbackStartTime + Date().timeIntervalSince(playbackStartedAt)
        } else {
            return
        }

        guard elapsed.isFinite else { return }
        if duration > 0, elapsed >= duration {
            resetPlayback()
            return
        }

        playbackTime = elapsed
        if !effectiveFrameTimes.isEmpty {
            currentFrame = effectiveFrameTimes.lastIndex(where: { $0 <= elapsed }) ?? 0
        }
    }
    
    func resetPlayback() {
        isPlaying = false
        currentFrame = 0
        playbackStartedAt = nil
        playbackStartTime = 0
        playbackTime = 0
        audioPlayer?.pause()
        audioPlayer?.seek(to: .zero)
    }
}
