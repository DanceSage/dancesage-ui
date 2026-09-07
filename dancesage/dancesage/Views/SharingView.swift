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
    @State private var chosen = false
    @State private var grants: [PlatformGrant] = []
    @State private var inbox: [SharedFrom] = []
    @State private var offers: [SharedFrom] = []
    @State private var groupsIn: [PlatformGroup] = []
    @State private var groupsOwned: [PlatformGroup] = []
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?
    @State private var opened: PlatformVideo?
    @State private var openedFrom = ""

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
                .onChange(of: direction) { _, _ in chosen = true }
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
        .fullScreenCover(item: $opened) { PlatformVideoDetailView(video: $0, teacherName: openedFrom) }
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
                            Text(g.accepted == false ? "\(g.scope) · waiting for their yes" : g.scope)
                                .font(.caption).foregroundStyle(g.accepted == false ? .orange : .white.opacity(0.5))
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(g.accepted == false ? "Withdraw" : "Revoke", role: .destructive) {
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
            if !groupsIn.isEmpty || !groupsOwned.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Groups")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                    ForEach(groupsOwned + groupsIn) { g in
                        NavigationLink { GroupWallView(groupID: g.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.3.fill").foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(g.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(g.owner.map { "from \($0.display_name)" } ?? "yours · \(g.members.count) members")
                                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.white.opacity(0.4))
                            }
                            .padding(12)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Offers first: a yes or a no is the thing waiting on you.
            if !offers.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Offers")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                        .textCase(.uppercase)
                    ForEach(offers) { from in
                        ForEach(from.videos) { v in
                            HStack(spacing: 12) {
                                AvatarDot(handle: from.handle, avatar: from.avatar,
                                          name: from.display_name, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text("from \(from.display_name.isEmpty ? "@\(from.handle)" : from.display_name)")
                                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                                }
                                Spacer()
                                if let grantID = v.grant_id {
                                    Button("Accept") { Task { await accept(grantID) } }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                        .disabled(busy)
                                    Button("Decline", role: .destructive) { Task { await decline(grantID) } }
                                        .font(.caption.weight(.medium))
                                        .disabled(busy)
                                }
                            }
                            .padding(12)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                }
            }

            if inbox.isEmpty && offers.isEmpty {
                blank("tray", "Nothing shared with you",
                      "When someone offers you a clip, it appears here to accept or decline.")
            } else if !inbox.isEmpty {
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
                                VStack(spacing: 6) {
                                    FeedCard(video: v, showByline: false) {
                                        openedFrom = from.display_name.isEmpty ? "@\(from.handle)" : from.display_name
                                        opened = v.asPlatformVideo
                                    }
                                    if let grantID = v.grant_id {
                                        Button("Stop", role: .destructive) {
                                            Task { await decline(grantID) }
                                        }
                                        .font(.caption.weight(.medium))
                                        .disabled(busy)
                                    }
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
        async let inb = try? DanceSagePlatform.shared.inbox()
        async let gs = try? DanceSagePlatform.shared.allGroups()
        let all = await gs
        groupsOwned = all?.groups ?? []
        groupsIn = all?.member_of ?? []
        grants = await out ?? []
        let mail = await inb
        inbox = mail?.from ?? []
        offers = mail?.offers ?? []
        // Someone shared something with you and you haven't picked a side yet:
        // open on that. It is the reason you came.
        if !chosen, !(inbox.isEmpty && offers.isEmpty && groupsIn.isEmpty) { direction = .incoming }
        loading = false
    }

    private func accept(_ grantID: Int) async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.accept(grantID: grantID)
            await load()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    /// Declines an offer or stops an accepted share; it leaves the sender's ledger too.
    private func decline(_ grantID: Int) async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.decline(grantID: grantID)
            await load()
        } catch { self.error = error.localizedDescription }
        busy = false
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
