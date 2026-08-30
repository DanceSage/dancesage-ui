import SwiftUI

/// Access, both directions, on one screen.
///
/// These were two menu items — "who I share with" and "what was shared with me" —
/// which is one idea split in half and hidden in two places. Access has two ends;
/// a person thinking about it is thinking about both.
struct SharingView: View {
    private enum Direction: String, CaseIterable, Identifiable {
        case out = "People I share with"
        case incoming = "Shared with me"
        var id: String { rawValue }
    }

    @State private var direction: Direction = .out
    @State private var grants: [PlatformGrant] = []
    @State private var inbox: [SharedFrom] = []
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?
    @State private var opened: PlatformVideo?

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                Picker("", selection: $direction) {
                    ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
                .padding(.horizontal, 16)
                .padding(.top, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error {
                            Text(error).font(.footnote).foregroundStyle(.red)
                        }
                        if loading {
                            ProgressView().tint(.white).frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if direction == .out {
                            outgoing
                        } else {
                            incoming
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
        .fullScreenCover(item: $opened) { PlatformVideoDetailView(video: $0) }
    }

    // MARK: - Outward

    private var outgoing: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Access is per video, so there is nothing to add from here — this is
            // the ledger of what you have already given, and where you take it back.
            Text("Access is per video. Open a recording on your profile and use "
                 + "Share this one to give someone that clip — they see it and "
                 + "nothing else.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))

            if grants.isEmpty {
                blank("person.2", "Nobody yet",
                      "People you share a video with appear here.")
            } else {
                ForEach(grants) { g in
                    HStack(spacing: 13) {
                        AvatarDot(handle: g.handle, avatar: g.avatar,
                                  name: g.display_name, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.display_name.isEmpty ? "@\(g.handle)" : g.display_name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            // Says what they can actually see, not just that they can.
                            Text(g.scope)
                                .font(.caption).foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Remove", role: .destructive) {
                            Task { await revoke(g) }
                        }
                        .font(.caption.weight(.medium))
                        .disabled(busy)
                    }
                    .padding(13)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Inward

    private var incoming: some View {
        VStack(alignment: .leading, spacing: 24) {
            if inbox.isEmpty {
                blank("tray", "Nothing shared with you",
                      "When someone gives you access, their moves appear here.")
            } else {
                ForEach(inbox) { from in
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 9) {
                            AvatarDot(handle: from.handle, avatar: from.avatar,
                                      name: from.display_name, size: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(from.display_name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text("@\(from.handle)")
                                    .font(.caption2).foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                            GridItem(.flexible(), spacing: 12)],
                                  spacing: 12) {
                            ForEach(from.videos) { v in
                                FeedCard(video: v, showByline: false) {
                                    opened = v.asPlatformVideo
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func blank(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 34)).foregroundStyle(.white.opacity(0.3))
            Text(title).font(.headline).foregroundStyle(.white.opacity(0.8))
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 42)
    }

    // MARK: - Work

    private func load() async {
        async let out = try? DanceSagePlatform.shared.grants()
        async let inb = try? DanceSagePlatform.shared.sharedWithMe()
        grants = await out ?? []
        inbox = await inb ?? []
        loading = false
    }

    private func revoke(_ g: PlatformGrant) async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.revoke(grantID: g.id)
            await load()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
