import SwiftUI

/// Your groups: make one, add people by handle, take people out, delete it.
/// Being in a group shares nothing by itself — it is a shorthand for Group share.
struct GroupsView: View {
    var onChanged: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var groups: [PlatformGroup] = []
    @State private var newName = ""
    @State private var handles: [Int: String] = [:]
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }

                ForEach(groups) { g in
                    Section {
                        if g.members.isEmpty {
                            Text("Nobody yet").foregroundStyle(.secondary).font(.subheadline)
                        }
                        ForEach(g.members) { m in
                            HStack {
                                Label("@\(m.handle ?? m.display_name)", systemImage: "person.fill")
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    Task { await remove(m.handle ?? "", from: g) }
                                }
                                .font(.caption.weight(.medium))
                                .disabled(busy)
                            }
                        }
                        HStack(spacing: 2) {
                            Text("@").foregroundStyle(.secondary)
                            TextField("add a dancer's handle", text: binding(for: g.id))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { Task { await add(to: g) } }
                            Button("Add") { Task { await add(to: g) } }
                                .font(.subheadline.weight(.semibold))
                                .disabled(busy || (handles[g.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        HStack {
                            NavigationLink { GroupWallView(groupID: g.id) } label: {
                                Label(g.name, systemImage: "arrow.right.circle").textCase(nil)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) { Task { await delete(g) } }
                                .font(.caption)
                                .disabled(busy)
                        }
                    }
                }

                Section {
                    TextField("A name, e.g. Tuesday bachata", text: $newName)
                    Button("Create group") { Task { await create() } }
                        .disabled(busy || newName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("New group")
                } footer: {
                    Text("Then add people to it above. Sharing with a group offers the clip to everyone in it.")
                }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.disabled(busy)
                }
            }
            .overlay { if loading { ProgressView() } }
        }
        .task { await load() }
    }

    private func binding(for id: Int) -> Binding<String> {
        Binding(get: { handles[id] ?? "" }, set: { handles[id] = $0 })
    }

    private func load() async {
        groups = (try? await DanceSagePlatform.shared.groups()) ?? []
        loading = false
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true; error = nil
        do { try await work(); await load(); await onChanged() }
        catch { self.error = error.localizedDescription }
        busy = false
    }

    private func create() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        await run { _ = try await DanceSagePlatform.shared.createGroup(name: name, handles: []); newName = "" }
    }

    private func add(to g: PlatformGroup) async {
        let h = (handles[g.id] ?? "").trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !h.isEmpty else { return }
        await run { try await DanceSagePlatform.shared.addToGroup(groupID: g.id, handle: h); handles[g.id] = "" }
    }

    private func remove(_ handle: String, from g: PlatformGroup) async {
        await run { try await DanceSagePlatform.shared.removeFromGroup(groupID: g.id, handle: handle) }
    }

    private func delete(_ g: PlatformGroup) async {
        await run { try await DanceSagePlatform.shared.deleteGroup(id: g.id) }
    }
}
