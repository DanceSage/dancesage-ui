import SwiftUI

/// A group's wall, as a tree: series, then video, then the attempts under it.
/// The owner sees everything members sent back; a member sees the lessons and
/// their own replies, and can share one of their posts back — no offer, it
/// just arrives.
struct GroupWallView: View {
    let groupID: Int

    @State private var wall: GroupWall?
    @State private var error: String?
    @State private var opened: PlatformVideo?
    @State private var openedSeries: String?
    @State private var pickingReply = false
    @State private var myPosts: [PlatformVideo] = []
    @State private var busy = false
    @State private var expanded: Set<Int> = []

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if let wall {
                        header(wall)

                        ForEach(wall.series) { sr in
                            Label(sr.name, systemImage: "folder.fill")
                                .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                                .padding(.top, 6)
                            ForEach(sr.videos) { l in
                                lessonRow(l, wall: wall, series: sr.name).padding(.leading, 12)
                            }
                        }

                        if !wall.lessons.isEmpty, !wall.series.isEmpty {
                            Text("Other videos").font(.subheadline.weight(.bold)).foregroundStyle(.white).padding(.top, 6)
                        }
                        ForEach(wall.lessons) { l in
                            lessonRow(l, wall: wall, series: nil)
                        }
                        if wall.lessons.isEmpty && wall.series.isEmpty {
                            Text(wall.group.mine ? "Nothing shared with the group yet — use Group share on a post or a series."
                                                 : "Nothing shared with the group yet.")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.6))
                        }

                        if !wall.group.mine {
                            Button {
                                pickingReply = true
                            } label: {
                                Label("Share one of your posts back", systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(Color.orange, in: Capsule())
                            }
                            .disabled(busy)
                            .padding(.top, 6)
                        }

                        if !wall.replies.isEmpty {
                            DisclosureGroup(isExpanded: binding(for: -1)) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(wall.replies) { r in
                                        Button { opened = r.asPlatformVideo } label: { replyLine(r) }
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                HStack {
                                    Text(wall.group.mine ? "Other videos shared back" : "Other videos you shared back")
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Spacer()
                                    Text("\(wall.replies.count)").font(.caption).foregroundStyle(.white.opacity(0.55))
                                }
                            }
                            .tint(.orange)
                            .padding(12)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }
                    } else {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(wall?.group.name ?? "Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $opened) {
            PlatformVideoDetailView(video: $0,
                                    teacherName: wall?.group.owner.display_name ?? "",
                                    groupID: groupID, groupName: wall?.group.name,
                                    seriesName: openedSeries)
        }
        .confirmationDialog("Share back to the group", isPresented: $pickingReply, titleVisibility: .visible) {
            ForEach(myPosts) { v in
                Button(v.title) { Task { await shareBack(v) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes to \(wall?.group.owner.display_name ?? "the owner") — nobody else — filed under this group.")
        }
    }

    // MARK: - Pieces

    private func header(_ w: GroupWall) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(w.group.name).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(w.group.mine
                 ? "Your group · " + w.group.members.map { "@\($0.handle ?? "")" }.joined(separator: ", ")
                 : "From \(w.group.owner.display_name)")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    /// One video: folds open on the attempts under it.
    private func lessonRow(_ l: GroupWall.Lesson, wall: GroupWall, series: String?) -> some View {
        DisclosureGroup(isExpanded: binding(for: l.id)) {
            VStack(alignment: .leading, spacing: 8) {
                Button { openedSeries = series; opened = l.video } label: {
                    Label("Watch the video", systemImage: "play.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                if wall.group.mine, !l.members.isEmpty {
                    FlowLayout(spacing: 5) {
                        ForEach(l.members.indices, id: \.self) { i in
                            let m = l.members[i]
                            Text(m.accepted ? "@\(m.handle ?? "")" : "@\(m.handle ?? "") · waiting")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(m.accepted ? .white.opacity(0.8) : .orange)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(.white.opacity(0.1), in: Capsule())
                        }
                    }
                }
                if l.replies.isEmpty {
                    Text(wall.group.mine ? "No attempts yet." : "You have not shared an attempt at this one yet.")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                }
                ForEach(l.replies) { r in
                    Button { opened = r.asPlatformVideo } label: { replyLine(r) }
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(l.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text(wall.group.mine
                     ? "\(l.replies.count) attempt\(l.replies.count == 1 ? "" : "s") · \(l.members.filter(\.accepted).count)/\(l.members.count) accepted"
                     : "\(l.replies.count) of yours")
                    .font(.caption).foregroundStyle(.white.opacity(0.55))
            }
        }
        .tint(.orange)
        .padding(12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func replyLine(_ r: FeedVideo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right").font(.caption2)
            Text(r.by.display_name).font(.subheadline.weight(.semibold))
            Text("· \(r.title)").font(.subheadline).lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right").font(.caption2)
        }
        .foregroundStyle(.white.opacity(0.9))
    }

    private func binding(for id: Int) -> Binding<Bool> {
        Binding(get: { expanded.contains(id) },
                set: { open in if open { expanded.insert(id) } else { expanded.remove(id) } })
    }

    // MARK: - Work

    private func load() async {
        do {
            wall = try await DanceSagePlatform.shared.wall(groupID: groupID)
            if expanded.isEmpty, let first = wall?.series.first?.videos.first?.id ?? wall?.lessons.first?.id {
                expanded.insert(first)
            }
            if wall?.group.mine == false {
                myPosts = (try? await DanceSagePlatform.shared.me().videos) ?? []
            }
        } catch { self.error = error.localizedDescription }
    }

    private func shareBack(_ v: PlatformVideo) async {
        busy = true; error = nil
        do { try await DanceSagePlatform.shared.shareBack(groupID: groupID, videoID: v.id); await load() }
        catch { self.error = error.localizedDescription }
        busy = false
    }
}
