import SwiftUI

/// Share one video with named people.
///
/// A grant can name a single video, and the server hides every other one from
/// that viewer — so this gives someone exactly this clip and nothing else.
struct ShareVideoView: View {
    let video: PlatformVideo
    var onChanged: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var shared: [PlatformGrant] = []
    @State private var groups: [PlatformGroup] = []
    @State private var newGroupName = ""
    @State private var newGroupHandles = ""
    @State private var shownGroupMaker = false
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("their handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await add() } }
                        Button("Add") { Task { await add() } }
                            .font(.subheadline.weight(.semibold))
                            .disabled(busy || handle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Share “\(video.title)”")
                } footer: {
                    Text("Only this video becomes visible to them. Everything else "
                         + "you have stays hidden.")
                }

                Section {
                    ForEach(groups) { g in
                        Button {
                            Task { await share(group: g) }
                        } label: {
                            HStack {
                                Label(g.name, systemImage: "person.3.fill")
                                Spacer()
                                Text(g.members.count == 1 ? "1 person" : "\(g.members.count) people")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(busy || g.members.isEmpty)
                    }
                    if shownGroupMaker {
                        TextField("Group name", text: $newGroupName)
                        TextField("@handles, comma-separated", text: $newGroupHandles)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Create group") { Task { await createGroup() } }
                            .disabled(busy || newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
                    } else {
                        Button {
                            shownGroupMaker = true
                        } label: {
                            Label("New group", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Or a whole group")
                } footer: {
                    Text("Tap a group to give everyone in it this video. Being in a group shares nothing by itself.")
                }

                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }

                Section {
                    if loading {
                        ProgressView()
                    } else if shared.isEmpty {
                        Text("Nobody yet").foregroundStyle(.secondary).font(.subheadline)
                    } else {
                        ForEach(shared) { g in
                            HStack {
                                Label("@\(g.handle)", systemImage: "person.fill")
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    Task { await revoke(g) }
                                }
                                .font(.caption.weight(.medium))
                                .disabled(busy)
                            }
                        }
                    }
                } header: {
                    Text("Who can see this one")
                }
            }
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(busy)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        async let all = try? DanceSagePlatform.shared.grants()
        async let mine = try? DanceSagePlatform.shared.groups()
        shared = (await all ?? []).filter { $0.video_id == video.id }
        groups = await mine ?? []
        loading = false
    }

    private func share(group: PlatformGroup) async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.grant(groupID: group.id, videoID: video.id)
            await load()
            await onChanged()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func createGroup() async {
        busy = true; error = nil
        let handles = newGroupHandles
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "") }
            .filter { !$0.isEmpty }
        do {
            _ = try await DanceSagePlatform.shared.createGroup(
                name: newGroupName.trimmingCharacters(in: .whitespaces), handles: handles)
            newGroupName = ""; newGroupHandles = ""; shownGroupMaker = false
            await load()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func add() async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.grant(
                handle: handle.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "@", with: ""),
                videoID: video.id)
            handle = ""
            await load()
            // Sharing marks the video Shared on the server; keep the profile honest.
            await onChanged()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func revoke(_ g: PlatformGrant) async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.revoke(grantID: g.id)
            await load()
            await onChanged()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
