import SwiftUI

/// A group's wall. The owner sees what they shared and everything members
/// sent back; a member sees the lessons and their own replies, and can share
/// one of their posts back — no offer, it just arrives.
struct GroupWallView: View {
    let groupID: Int

    @State private var wall: GroupWall?
    @State private var error: String?
    @State private var opened: PlatformVideo?
    @State private var pickingReply = false
    @State private var myPosts: [PlatformVideo] = []
    @State private var busy = false

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if let wall {
                        header(wall)
                        section(wall.group.mine ? "What you shared with the group" : "Shared with the group",
                                empty: wall.group.mine ? "Use Group share on one of your posts." : "Accept the offer on your profile to watch it.") {
                            ForEach(wall.lessons) { l in
                                VStack(alignment: .leading, spacing: 6) {
                                    Button { opened = l.video } label: { lessonCard(l) }.buttonStyle(.plain)
                                    if wall.group.mine {
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
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 10) {
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
                            }
                            section(wall.group.mine ? "Shared back by members" : "What you shared back",
                                    empty: "Nothing yet.") {
                                ForEach(wall.replies) { v in
                                    FeedCard(video: v, showByline: wall.group.mine) { opened = v.asPlatformVideo }
                                }
                            }
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
        .fullScreenCover(item: $opened) { PlatformVideoDetailView(video: $0) }
        .confirmationDialog("Share back to the group", isPresented: $pickingReply, titleVisibility: .visible) {
            ForEach(myPosts) { v in
                Button(v.title) { Task { await shareBack(v) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It goes to \(wall?.group.owner.display_name ?? "the owner") — nobody else — filed under this group.")
        }
    }

    private func header(_ w: GroupWall) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(w.group.name).font(.title2.weight(.bold)).foregroundStyle(.white)
            Text(w.group.mine
                 ? "Your group · " + w.group.members.map { "@\($0.handle ?? "")" }.joined(separator: ", ")
                 : "From \(w.group.owner.display_name)")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    private func section<Content: View>(_ title: String, empty: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.6)).textCase(.uppercase)
            let grid = LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) { content() }
            grid
            Text(empty).font(.caption).foregroundStyle(.white.opacity(0.45)).opacity(0) // keeps spacing when empty
        }
    }

    private func lessonCard(_ l: GroupWall.Lesson) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SkeletonThumbnail(poseKey: l.pose_key).frame(height: 150).frame(maxWidth: .infinity).background(.black.opacity(0.28))
            Text(l.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(11)
        }
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func load() async {
        do {
            wall = try await DanceSagePlatform.shared.wall(groupID: groupID)
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
