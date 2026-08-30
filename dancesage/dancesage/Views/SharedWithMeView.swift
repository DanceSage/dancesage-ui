import SwiftUI

/// What other people have let you see, grouped by who shared it.
///
/// The inbound half of a grant. Grouping by person rather than mixing everything
/// together matters — you remember *who* showed you a move, not what it was called.
struct SharedWithMeView: View {
    @State private var groups: [SharedFrom] = []
    @State private var loading = true
    @State private var error: String?
    @State private var opened: PlatformVideo?

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if loading {
                ProgressView().tint(.white)
            } else if groups.isEmpty {
                empty
            } else {
                list
            }
        }
        .navigationTitle("Shared with me")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $opened) { PlatformVideoDetailView(video: $0) }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 9) {
                            AvatarDot(handle: group.handle, avatar: group.avatar,
                                      name: group.display_name, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(group.display_name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("@\(group.handle)")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            ForEach(group.videos) { video in
                                FeedCard(video: video, showByline: false) {
                                    opened = video.asPlatformVideo
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 38)).foregroundStyle(.white.opacity(0.3))
            Text("Nothing shared with you")
                .font(.headline).foregroundStyle(.white.opacity(0.8))
            Text("When someone gives you access, their shared moves appear here.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func load() async {
        do {
            groups = try await DanceSagePlatform.shared.sharedWithMe()
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }
}
