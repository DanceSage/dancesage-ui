import SwiftUI

/// Your Dance Sage profile, in the app.
///
/// Deliberately the same shape as the web page at `/@handle` — same header, same
/// grid, same visibility control. One profile, two surfaces; the phone is the one
/// that can also change things.
struct PlatformProfileView: View {
    @ObservedObject private var auth = DanceSageAuth.shared
    @ObservedObject private var lock = BiometricLock.shared
    @State private var profile: PlatformProfile?
    @State private var error: String?
    @State private var loading = true
    @State private var showSignIn = false
    @State private var opened: PlatformVideo?
    @State private var showSharing = false
    /// Videos other people let you see — so the way in is visible, not a menu item.
    @State private var sharedWithMe: [SharedFrom] = []
    @State private var offers: [SharedFrom] = []
    /// Who can see which of your posts — painted on every card.
    @State private var grants: [PlatformGrant] = []
    @State private var showDelete = false
    /// What is waiting on a yes. One alert per view is all SwiftUI reliably
    /// presents; two of them means one silently never fires.
    private enum Pending: Identifiable {
        case post(PlatformVideo)
        case recording(DanceRecording)
        var id: String {
            switch self {
            case .post(let v): return "post-\(v.id)"
            case .recording(let r): return "rec-\(r.id)"
            }
        }
        var title: String {
            switch self {
            case .post: return "Delete this post?"
            case .recording: return "Delete this recording?"
            }
        }
        var message: String {
            switch self {
            case .post(let v):
                return "“\(v.title)” and its skeleton are removed from Dance Sage. "
                     + "The recording on this iPhone is not deleted."
            case .recording(let r):
                return "“\(r.name)” is removed from this iPhone. "
                     + "Anything you already posted stays on your profile."
            }
        }
    }
    @State private var pending: Pending?
    @State private var shareOne: PlatformVideo?
    @State private var recordings: [DanceRecording] = []
    @State private var playing: DanceRecording?
    @State private var posting: DanceRecording?

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            if !auth.isSignedIn {
                signedOut
            } else if lock.isLocked {
                locked
            } else if loading {
                ProgressView().tint(.white)
            } else if let profile {
                content(profile)
            } else {
                failed
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            if auth.isSignedIn {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if BiometricLock.shared.available {
                            Button(lock.isEnabled
                                   ? "Turn off \(lock.kindName)"
                                   : "Turn on \(lock.kindName)") {
                                lock.isEnabled ? lock.disable() : lock.enable()
                            }
                        }
                        Button {
                            showSharing = true
                        } label: {
                            let n = sharedWithMe.reduce(0) { $0 + $1.videos.count }
                            let o = offers.reduce(0) { $0 + $1.videos.count }
                            Label(o > 0 ? "Sharing · \(o) to accept" : (n > 0 ? "Sharing · \(n) shared with you" : "Sharing"),
                                  systemImage: "person.2.fill")
                        }
                        Divider()
                        Button("Sign out") { auth.signOut() }
                        Button("Delete account", role: .destructive) {
                            showDelete = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task { await load(); loadRecordings() }
        .onChange(of: profile?.videos.count) { _, _ in loadRecordings() }
        .refreshable { await load(); loadRecordings() }
        .fullScreenCover(isPresented: $showSignIn) {
            AccountView(start: .signIn)
        }
        .navigationDestination(isPresented: $showSharing) { SharingView() }
        .sheet(item: $shareOne) { video in
            ShareVideoView(video: video) { await load() }
        }
        .sheet(isPresented: $showDelete) {
            DeleteAccountView(postCount: profile?.videos.count ?? 0)
        }
        .alert(pending?.title ?? "", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }
        ), presenting: pending) { item in
            Button("Delete", role: .destructive) {
                switch item {
                case .post(let v): Task { await remove(v) }
                case .recording(let r): removeLocal(r)
                }
            }
            Button("Keep", role: .cancel) { pending = nil }
        } message: { item in
            Text(item.message)
        }
        .fullScreenCover(item: $playing) { recording in
            SkeletonPlaybackView(
                keypoints: recording.keypoints,
                allowSave: false,
                useVisionIndices: recording.mode == .partner,
                beats: recording.beats ?? [],
                bpm: recording.bpm ?? 0,
                fps: recording.fps ?? 15,
                frameTimes: recording.frameTimes ?? [],
                worldKeypoints: recording.worldKeypoints ?? [],
                recordingMode: recording.mode ?? .styling,
                videoURL: RecordingStore.shared.existingVideoURL(for: recording),
                cameraPosition: recording.cameraPosition
            )
        }
        .sheet(item: $posting) { recording in
            PostRecordingView(
                keypoints: recording.keypoints,
                world: recording.worldKeypoints ?? [],
                frameTimes: recording.frameTimes ?? [],
                fps: recording.fps ?? 15,
                videoURL: RecordingStore.shared.existingVideoURL(for: recording),
                suggestedTitle: recording.name
            ) { newID in
                try? RecordingStore.shared.markPosted(recording, videoID: newID)
                loadRecordings()
                Task { await load() }
            }
        }
        .fullScreenCover(item: $opened) { video in
            PlatformVideoDetailView(
                video: video,
                onVisibilityChange: { visibility in
                    await change(video, to: visibility)
                    opened = nil
                },
                onShared: { await load() },
                onDelete: {
                    opened = nil
                    pending = .post(video)
                }
            )
        }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            if signedIn { Task { await load() } }
        }
    }

    // MARK: - States

    private var signedOut: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 54))
                .foregroundStyle(.orange)
            Text("Your profile lives on Dance Sage")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Sign in to see the videos and skeletons you have posted — the same page people see on the web.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)
            Button("Sign in") { showSignIn = true }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 34)
                .padding(.vertical, 13)
                .background(.orange, in: Capsule())
        }
        .padding(34)
    }

    /// A session exists but this launch has not proved who is holding the phone.
    private var locked: some View {
        VStack(spacing: 18) {
            Image(systemName: "faceid")
                .font(.system(size: 50))
                .foregroundStyle(.orange)
            Text("Locked")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Unlock with \(lock.kindName) to see your profile.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.66))
            Button("Unlock") { Task { await unlock() } }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, 34)
                .padding(.vertical, 13)
                .background(.orange, in: Capsule())
            Button("Sign out") { auth.signOut() }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(34)
        .task { await unlock() }
    }

    private func unlock() async {
        if await lock.unlock() { await load() }
    }

    private var failed: some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
            Text(error ?? "Could not load your profile.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Try again") { Task { await load() } }
                .font(.subheadline.bold())
                .foregroundStyle(.orange)
        }
        .padding(34)
    }

    private func content(_ p: PlatformProfile) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                header(p)

                // What others let you see, one tap from the top of your own page —
                // not a segment inside a menu item.
                let sharedCount = sharedWithMe.reduce(0) { $0 + $1.videos.count }
                let offerCount = offers.reduce(0) { $0 + $1.videos.count }
                if sharedCount + offerCount > 0 {
                    Button {
                        showSharing = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 40, height: 40)
                                .background(.orange.opacity(0.16), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(offerCount > 0
                                     ? (offerCount == 1 ? "1 clip offered to you" : "\(offerCount) clips offered to you")
                                     : (sharedCount == 1 ? "1 video shared with you" : "\(sharedCount) videos shared with you"))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text((offerCount > 0 ? "accept or decline · from " : "from ")
                                     + (offerCount > 0 ? offers : sharedWithMe).map { $0.display_name.isEmpty ? "@\($0.handle)" : $0.display_name }
                                        .formatted(.list(type: .and)))
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(14)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)) }
                    }
                    .buttonStyle(.plain)
                }

                // Errors used to be recorded and never shown, so a failed delete
                // looked exactly like a button that does nothing.
                if let error {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error).font(.footnote)
                        Spacer(minLength: 0)
                        Button {
                            self.error = nil
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                    }
                    .foregroundStyle(.orange)
                    .padding(12)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }

                if p.videos.isEmpty && recordings.isEmpty {
                    empty
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                        GridItem(.flexible(), spacing: 12)],
                              spacing: 12) {
                        // On this iPhone first — the newest thing you did is the
                        // thing you came back to look at.
                        ForEach(recordings) { recording in
                            LocalRecordingCard(recording: recording) {
                                playing = recording
                            } onPost: {
                                posting = recording
                            } onDelete: {
                                pending = .recording(recording)
                            }
                        }
                        // Newest first, whatever order the server sent — same as the web.
                        ForEach(p.videos.sorted { $0.id > $1.id }) { video in
                            VideoCard(video: video, sharedWith: grants.filter { $0.video_id == video.id }) { visibility in
                                await change(video, to: visibility)
                            } onOpen: {
                                opened = video
                            } onDelete: {
                                pending = .post(video)
                            } onShare: {
                                shareOne = video
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 30)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.dance")
                .font(.system(size: 38))
                .foregroundStyle(.white.opacity(0.35))
            Text("Nothing here yet")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            Text("Record a move on the Record tab. It lands here, and stays on this iPhone until you post it.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 46)
    }

    private func header(_ p: PlatformProfile) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                avatar(p)
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .overlay { Circle().stroke(.white.opacity(0.16)) }

                VStack(alignment: .leading, spacing: 4) {
                    Text(p.display_name.isEmpty ? "Dancer" : p.display_name)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("@\(p.handle)" + (p.city.isEmpty ? "" : " · \(p.city)"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
            }

            if !p.bio.isEmpty {
                Text(p.bio)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // The same four numbers as the web: what you posted, and who can see it.
            HStack(spacing: 0) {
                stat("\(p.videos.count)", "total")
                stat("\(p.videos.filter { $0.visibility == "public" }.count)", "public")
                stat("\(p.videos.filter { $0.visibility != "public" }.count)", "private")
                stat("\(Set(grants.map(\.video_id)).count)", "shared")
            }
            .padding(.vertical, 12)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 8)
    }

    /// The photo when there is one, initials when there is not.
    @ViewBuilder
    private func avatar(_ p: PlatformProfile) -> some View {
        if let url = p.avatarURL(base: AppConfig.platformBaseURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    initialsCircle(p)
                default:
                    Circle().fill(.white.opacity(0.12))
                        .overlay { ProgressView().tint(.white) }
                }
            }
        } else {
            initialsCircle(p)
        }
    }

    private func initialsCircle(_ p: PlatformProfile) -> some View {
        Circle()
            .fill(.white.opacity(0.12))
            .overlay {
                Text(initials(p))
                    .font(.title2.bold())
                    .foregroundStyle(.orange)
            }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func initials(_ p: PlatformProfile) -> String {
        let source = p.display_name.isEmpty ? p.handle : p.display_name
        return source.split(separator: " ").prefix(2)
            .compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    // MARK: - Work

    /// Straight off the device — no network, so it fills in even with the server down.
    private func loadRecordings() {
        // A recording that became a post is shown by its post, not twice.
        let posts = profile?.videos ?? []
        let byID = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0) })
        var all = (try? RecordingStore.shared.load()) ?? []

        // A link is only good if the post it names is still the same dance. Video
        // ids get reused when one is deleted, so a recording can end up pointing
        // at somebody else's later post — and then hide itself for good behind a
        // card that is not it.
        for r in all where r.postedVideoID != nil {
            let post = byID[r.postedVideoID!]
            if post == nil && byID.isEmpty { continue }   // profile not loaded yet
            if let post, post.frames == r.frameCount { continue }
            if post != nil {
                try? RecordingStore.shared.unlinkPost(r)
            }
        }
        all = (try? RecordingStore.shared.load()) ?? []
        let postedIDs = Set(posts.filter { post in
            all.contains { $0.postedVideoID == post.id && $0.frameCount == post.frames }
        }.map(\.id))

        // Recordings posted before the app started recording the link have no id
        // to match on. Rather than leave them showing as unposted forever, pair
        // them by what they are — same name, same length — and write the link so
        // the guess is made once.
        var claimed = Set(all.compactMap(\.postedVideoID))
        for r in all where r.postedVideoID == nil {
            // Same title is the strong signal; same length alone is enough when
            // the title was edited while posting. A post can only be claimed once.
            let candidates = posts.filter { !claimed.contains($0.id)
                                            && $0.frames == r.frameCount }
            if let match = candidates.first(where: { $0.title == r.name })
                        ?? candidates.first {
                claimed.insert(match.id)
                try? RecordingStore.shared.markPosted(r, videoID: match.id)
            }
        }

        recordings = ((try? RecordingStore.shared.load()) ?? [])
            .filter { r in r.postedVideoID.map { !postedIDs.contains($0) } ?? true }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func load() async {
        guard auth.isSignedIn, !lock.isLocked else { loading = false; return }
        loading = profile == nil

        // The first request to a LAN address fails while iOS is still deciding about
        // local network access, so a cold open would show an error the user never
        // caused. Retry once quietly before saying anything went wrong.
        for attempt in 0..<2 {
            do {
                profile = try await DanceSagePlatform.shared.me()
                let mail = try? await DanceSagePlatform.shared.inbox()
                sharedWithMe = mail?.from ?? []
                offers = mail?.offers ?? []
                grants = (try? await DanceSagePlatform.shared.grants()) ?? []
                error = nil
                loading = false
                return
            } catch let e as PlatformError {
                if case .notSignedIn = e { auth.signOut(); error = e.localizedDescription; break }
                error = e.localizedDescription
            } catch {
                self.error = error.localizedDescription
                if attempt == 0 { try? await Task.sleep(for: .milliseconds(600)); continue }
            }
            break
        }
        loading = false
    }

    private func removeLocal(_ recording: DanceRecording) {
        pending = nil
        guard let all = try? RecordingStore.shared.load(),
              let index = all.firstIndex(where: { $0.id == recording.id }) else { return }
        do {
            _ = try RecordingStore.shared.delete(at: IndexSet(integer: index))
            loadRecordings()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ video: PlatformVideo) async {
        pending = nil
        do {
            try await DanceSagePlatform.shared.deleteVideo(id: video.id)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func change(_ video: PlatformVideo, to visibility: String) async {
        do {
            try await DanceSagePlatform.shared.setVisibility(videoID: video.id, to: visibility)
            await load()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - One post

private struct VideoCard: View {
    let video: PlatformVideo
    /// Everyone this post was shared with; a chip each, dimmed until they accept.
    var sharedWith: [PlatformGrant] = []
    let onVisibility: (String) async -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            openArea
            controls
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    /// Tapping the picture or the title opens the post.
    private var openArea: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                SkeletonThumbnail(poseKey: video.pose_key)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(.black.opacity(0.28))
                .overlay(alignment: .bottomTrailing) {
                    Text(video.duration)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(7)
                }

                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.top, 11)

                if !sharedWith.isEmpty {
                    GrantChips(grants: sharedWith)
                        .padding(.horizontal, 11)
                        .padding(.top, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The menu lives outside that button, so its taps reach it.
    private var controls: some View {
        HStack {
            Menu {
                Button("Public") { Task { await onVisibility("public") } }
                Button("Private") { Task { await onVisibility("private") } }
                Divider()
                Button("Share…", systemImage: "person.badge.plus", action: onShare)
                Button("Delete post", role: .destructive, action: onDelete)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: icon).font(.caption2)
                    Text(label).font(.caption.weight(.medium))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(tint)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tint.opacity(0.16), in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.top, 7)
        .padding(.bottom, 11)
    }

    private var label: String { video.visibility == "public" ? "Public" : "Private" }
    private var icon: String { video.visibility == "public" ? "globe" : "lock.fill" }
    private var tint: Color { video.visibility == "public" ? .green : .white.opacity(0.7) }
}

// MARK: - The skeleton

/// A card-sized loop of the track. Same renderer as the full player.
struct SkeletonThumbnail: View {
    let poseKey: String
    @State private var track: SkeletonTrack?

    var body: some View {
        Group {
            if let track {
                SkeletonTrackView(track: track, still: true)
            } else {
                Image(systemName: "figure.dance")
                    .font(.system(size: 26))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .task(id: poseKey) { track = await SkeletonTrack.load(key: poseKey) }
    }
}


/// `@andy`, `@leo · waiting` — who can see a post, at a glance.
struct GrantChips: View {
    let grants: [PlatformGrant]

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(grants) { g in
                let waiting = g.accepted == false
                Text(waiting ? "@\(g.handle) · waiting" : "@\(g.handle)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(waiting ? .orange : .white.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(waiting ? 0.06 : 0.1), in: Capsule())
                    .lineLimit(1)
            }
        }
    }
}

/// Wraps its children onto as many rows as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
