import SwiftUI
import AVKit

/// One post, full size — the app's version of the web's `/v/{id}`.
///
/// When there is a video, the video is the clock and the skeleton follows it. That
/// ordering matters: driving the skeleton from its own timer would let the two drift
/// apart over a long clip, and a skeleton that lags the body is worse than none.
struct PlatformVideoDetailView: View {
    let video: PlatformVideo
    /// Present only for the owner — and with it, the whole menu the profile has.
    var onVisibilityChange: ((String) async -> Void)? = nil
    var onShared: (() async -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    /// Who posted it, when opened from the inbox — becomes the lesson's teacher.
    var teacherName: String = ""
    /// The group it was shared through, when opened from one — a lesson made
    /// from it remembers, so attempts can go straight back there.
    var groupID: Int? = nil
    var groupName: String? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var track: SkeletonTrack?
    @State private var player: AVPlayer?
    @State private var mode: ViewMode = .both
    @State private var hiddenDancers: Set<Int> = []
    @State private var playhead: Double = 0
    @State private var isPlaying = true
    @State private var observer: Any?
    @State private var yaw: Double = 17 * .pi / 180     // the web's default Turn
    @State private var dragStart: Double = 0
    @State private var videoAspect: CGFloat?
    /// A posted lesson attempt: two dancers on one clock. Opens in the same
    /// replay the student used, so the teacher sees what they saw.
    @State private var replay: (reference: DanceRecording, attempt: DanceRecording)?
    @State private var showReplay = false
    @State private var sharedWith: [PlatformGrant] = []
    @State private var showShare = false
    @State private var namingLesson = false
    @State private var newLessonName = ""
    @State private var importing = false
    @State private var lessonMessage: String?

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
                if replay != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            player?.pause()
                            showReplay = true
                        } label: {
                            Label("Lesson Replay", systemImage: "figure.2")
                        }
                    }
                } else if !video.pose2d_key.isEmpty {
                    // A post you can see is a move you can practise: it comes down
                    // with its video, so the replay shows the teacher, not a ghost.
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            newLessonName = video.title
                            namingLesson = true
                        } label: {
                            if importing {
                                ProgressView().tint(.white)
                            } else {
                                Label("Add to My Lessons", systemImage: "graduationcap")
                            }
                        }
                        .disabled(importing)
                    }
                }
            }
            .alert("Name this lesson", isPresented: $namingLesson) {
                TextField("Lesson name", text: $newLessonName)
                Button("Save") { Task { await importAsLesson(named: newLessonName) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The move and its video come to this iPhone, and it appears in Lessons.")
            }
            .alert(lessonMessage?.hasPrefix("Couldn't") == true ? "Could Not Add Lesson" : "Added to Lessons",
                   isPresented: Binding(get: { lessonMessage != nil }, set: { if !$0 { lessonMessage = nil } })) {
                Button("OK", role: .cancel) { lessonMessage = nil }
            } message: {
                Text(lessonMessage ?? "")
            }
            .fullScreenCover(isPresented: $showReplay) {
                if let replay {
                    LessonOverlayView(reference: replay.reference, attempt: replay.attempt, mirrored: false, attemptLabel: "Student")
                }
            }
        }
        .task { await load(); await loadGrants(); await loadReplay() }
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
                        if mode.showsVideo, let player {
                            VideoPlayer(player: player).allowsHitTesting(false)
                        }
                        if let track, mode.showsSkeleton {
                            SkeletonTrackView(track: track, time: playhead,
                                              yaw: yaw, lineWidth: 3, hidden: hiddenDancers)
                        }
                    }
                    .aspectRatio(aspect, contentMode: .fit)
                } else if let track {
                    SkeletonTrackView(track: track, time: nil, yaw: yaw, lineWidth: 4, hidden: hiddenDancers)
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
                ViewModePicker(mode: $mode)
            }

            if let track, track.dancers.count > 1 {
                DancerToggles(
                    labels: replay != nil ? ["Teacher", "Student"]
                        : (0..<track.dancers.count).map { "Dancer \($0 + 1)" },
                    colors: SkeletonTrack.colours,
                    hidden: $hiddenDancers
                )
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
                // Someone else's public clip: pass it on. Their private clip shared
                // with you: nothing — it is theirs to share, not yours.
                if onVisibilityChange == nil, video.visibility == "public" {
                    Button {
                        player?.pause()
                        showShare = true
                    } label: {
                        Label("Share…", systemImage: "person.badge.plus")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.orange.opacity(0.16), in: Capsule())
                    }
                }
                if let onVisibilityChange {
                    Menu {
                        Button("Public") { Task { await onVisibilityChange("public") } }
                        Button("Private") { Task { await onVisibilityChange("private") } }
                        Divider()
                        Button("Share…", systemImage: "person.badge.plus") {
                            player?.pause()
                            showShare = true
                        }
                        if let onDelete {
                            Divider()
                            Button("Delete post", role: .destructive) {
                                dismiss()
                                onDelete()
                            }
                        }
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

            // Who can see it, right here — the same chips the profile card shows.
            if onVisibilityChange != nil, !sharedWith.isEmpty {
                GrantChips(grants: sharedWith)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
        .sheet(isPresented: $showShare) {
            ShareVideoView(video: video) {
                await loadGrants()
                await onShared?()
            }
        }
    }

    private func loadGrants() async {
        guard onVisibilityChange != nil else { return }
        sharedWith = ((try? await DanceSagePlatform.shared.grants()) ?? []).filter { $0.video_id == video.id }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.10), in: Capsule())
    }

    private var label: String { video.visibility == "public" ? "Public" : "Private" }
    private var icon: String { video.visibility == "public" ? "globe" : "lock.fill" }
    private var tint: Color { video.visibility == "public" ? .green : .white.opacity(0.7) }

    private func clock(_ t: Double) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    // MARK: - Becoming a lesson

    /// Pulls the post down as a lesson: the 2D track for the skeleton, the video
    /// when there is one, and beats found in that video's audio so the
    /// comparison can count.
    private func importAsLesson(named name: String) async {
        importing = true
        defer { importing = false }
        do {
            let raw = try await DanceSagePlatform.shared.poseTrack(key: video.pose2d_key)
            guard let dancer = raw.j.first, !dancer.isEmpty, raw.isTwoDimensional else {
                lessonMessage = "Couldn't add: this post has no usable skeleton."
                return
            }
            let keypoints: [[[CGPoint]]] = dancer.map { frame in
                [frame.map { CGPoint(x: $0.count > 0 ? $0[0] : -1, y: $0.count > 1 ? $0[1] : -1) }]
            }

            var downloaded: URL?
            var beats: [Double] = []
            var bpm: Double = 0
            if video.has_video {
                let remote = try await DanceSagePlatform.shared.playbackURL(videoID: video.id)
                let (temp, _) = try await URLSession.shared.download(from: remote)
                let kept = FileManager.default.temporaryDirectory.appendingPathComponent("lesson-\(video.id).mov")
                try? FileManager.default.removeItem(at: kept)
                try FileManager.default.moveItem(at: temp, to: kept)
                downloaded = kept
                (beats, bpm) = await withCheckedContinuation { continuation in
                    let detector = BeatDetector()
                    detector.detectBeats(from: kept) { found, foundBPM in
                        continuation.resume(returning: (found, foundBPM))
                    }
                }
            }

            let recording = DanceRecording(
                name: video.title,
                keypoints: keypoints,
                mode: .styling,
                fps: Double(max(raw.fps, 1)),
                frameTimes: raw.t ?? [],
                beats: beats,
                bpm: bpm,
                hasVideo: downloaded != nil
            )
            if let downloaded {
                let home = RecordingStore.shared.videoURL(for: recording)
                try FileManager.default.createDirectory(at: home.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: home)
                try FileManager.default.moveItem(at: downloaded, to: home)
            }
            let lesson = try LessonStore.shared.addLesson(
                recording: recording, teacherName: teacherName, name: name,
                sourceVideoID: video.id, sourceGroupID: groupID, sourceGroupName: groupName)
            lessonMessage = "“\(lesson.title)” is in your Lessons\(downloaded == nil ? "" : ", with the video"). Open Lessons to practise it."
        } catch {
            lessonMessage = "Couldn't add: \(error.localizedDescription)"
        }
    }

    // MARK: - Wiring

    /// Only a two-person 2D track is a lesson attempt; anything else has no
    /// teacher to compare against.
    private func loadReplay() async {
        guard !video.pose2d_key.isEmpty,
              let raw = try? await DanceSagePlatform.shared.poseTrack(key: video.pose2d_key),
              raw.j.count == 2, raw.isTwoDimensional else { return }
        func recording(_ dancer: [[[Double]]], named name: String) -> DanceRecording {
            DanceRecording(
                name: name,
                keypoints: dancer.map { frame in
                    [frame.map { CGPoint(x: $0.count > 0 ? $0[0] : -1, y: $0.count > 1 ? $0[1] : -1) }]
                },
                mode: .styling,
                fps: Double(max(raw.fps, 1)),
                frameTimes: raw.t ?? [],
                hasVideo: false
            )
        }
        replay = (recording(raw.j[0], named: "Teacher"), recording(raw.j[1], named: video.title))
    }

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
