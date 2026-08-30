import SwiftUI
import AVKit

/// One post, full size — the app's version of the web's `/v/{id}`.
///
/// When there is a video, the video is the clock and the skeleton follows it. That
/// ordering matters: driving the skeleton from its own timer would let the two drift
/// apart over a long clip, and a skeleton that lags the body is worse than none.
struct PlatformVideoDetailView: View {
    let video: PlatformVideo
    var onVisibilityChange: ((String) async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var track: SkeletonTrack?
    @State private var player: AVPlayer?
    @State private var mode: Mode = .both
    @State private var playhead: Double = 0
    @State private var isPlaying = true
    @State private var observer: Any?
    @State private var yaw: Double = 17 * .pi / 180     // the web's default Turn
    @State private var dragStart: Double = 0
    @State private var videoAspect: CGFloat?

    enum Mode: String, CaseIterable, Identifiable {
        case both = "Both", video = "Video", skeleton = "Skeleton"
        var id: String { rawValue }
    }

    private var hasVideo: Bool { video.has_video && player != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    stage
                    controls
                }
            }
            .navigationTitle(video.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await load() }
        .onDisappear { teardown() }
    }

    // MARK: - The picture

    private var stage: some View {
        GeometryReader { geo in
            ZStack {
                if hasVideo, let aspect = videoAspect {
                    // Player and overlay share one aspect-fitted box, so a normalised
                    // 2D track lands on the body instead of on the letterboxing.
                    ZStack {
                        if mode != .skeleton, let player {
                            VideoPlayer(player: player).allowsHitTesting(false)
                        }
                        if let track, mode != .video {
                            SkeletonTrackView(track: track, time: playhead,
                                              yaw: yaw, lineWidth: 3)
                        }
                    }
                    .aspectRatio(aspect, contentMode: .fit)
                } else if let track {
                    SkeletonTrackView(track: track, time: nil, yaw: yaw, lineWidth: 4)
                }
                if track == nil && !hasVideo {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Drag to turn a 3D skeleton, exactly as dragging the web canvas does.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        guard let track, track.hasDepth else { return }
                        if g.translation.width == 0 { dragStart = yaw }
                        yaw = dragStart + Double(g.translation.width) * 0.01
                    }
                    .onEnded { _ in dragStart = yaw }
            )
        }
    }

    // MARK: - The controls

    private var controls: some View {
        VStack(spacing: 14) {
            if hasVideo {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
            }

            if hasVideo, let track {
                HStack(spacing: 12) {
                    Button {
                        isPlaying.toggle()
                        isPlaying ? player?.play() : player?.pause()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 34)
                    }
                    Slider(value: Binding(
                        get: { playhead },
                        set: { seek(to: $0) }
                    ), in: 0...max(track.duration, 0.1))
                    .tint(.orange)
                    Text(clock(playhead))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if let track, track.hasDepth {
                HStack(spacing: 10) {
                    Text("Turn").font(.caption).foregroundStyle(.white.opacity(0.6))
                    Slider(value: $yaw, in: -Double.pi...Double.pi).tint(.orange)
                    Button {
                        withAnimation { yaw = 17 * .pi / 180 }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }

            HStack(spacing: 8) {
                tag(video.style)
                tag(video.level)
                Spacer()
                if let onVisibilityChange {
                    Menu {
                        Button("Public") { Task { await onVisibilityChange("public") } }
                        Button("Shared") { Task { await onVisibilityChange("granted") } }
                        Button("Private") { Task { await onVisibilityChange("private") } }
                    } label: {
                        Label(label, systemImage: icon)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(tint.opacity(0.16), in: Capsule())
                    }
                }
            }

            if !video.note.isEmpty {
                Text(video.note)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(.black)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.10), in: Capsule())
    }

    private var label: String {
        switch video.visibility {
        case "public": return "Public"
        case "granted": return "Shared"
        default: return "Private"
        }
    }
    private var icon: String {
        switch video.visibility {
        case "public": return "globe"
        case "granted": return "person.2.fill"
        default: return "lock.fill"
        }
    }
    private var tint: Color {
        switch video.visibility {
        case "public": return .green
        case "granted": return .orange
        default: return .white.opacity(0.7)
        }
    }

    private func clock(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    // MARK: - Wiring

    private func load() async {
        // The overlay track when there is video to sit on, the 3D one otherwise.
        track = await SkeletonTrack.load(key: video.has_video ? video.overlayKey
                                                             : video.pose_key)
        guard video.has_video,
              let url = try? await DanceSagePlatform.shared.playbackURL(videoID: video.id)
        else { return }

        let asset = AVURLAsset(url: url)
        if let vtrack = try? await asset.loadTracks(withMediaType: .video).first,
           let natural = try? await vtrack.load(.naturalSize),
           let transform = try? await vtrack.load(.preferredTransform) {
            let shown = natural.applying(transform)
            let w = abs(shown.width), h = abs(shown.height)
            if w > 0, h > 0 { videoAspect = w / h }
        }

        let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .none
        self.player = player

        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0 / 60, preferredTimescale: 600),
            queue: .main
        ) { time in
            playhead = time.seconds.isFinite ? time.seconds : 0
        }
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        player.play()
    }

    private func seek(to t: Double) {
        playhead = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func teardown() {
        if let observer { player?.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
    }
}
