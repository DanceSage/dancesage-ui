import SwiftUI

/// Share a series — every video in it now, and every one added later — with a
/// dancer or a group; see who has it; take it back; delete the folder.
struct SeriesShareView: View {
    let series: PlatformSeries
    var onChanged: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var handle = ""
    @State private var groups: [PlatformGroup] = []
    @State private var pickedGroup: Int?
    @State private var who: [PlatformSeries.Who] = []
    @State private var busy = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var showGroups = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField("their handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onSubmit { Task { await share(handle: handle) } }
                        Button("Share") { Task { await share(handle: handle) } }
                            .font(.subheadline.weight(.semibold))
                            .disabled(busy || handle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Share with a dancer")
                } footer: {
                    Text("They accept once and get every video in “\(series.name)”, and every one you add later.")
                }

                Section {
                    Picker("Group", selection: $pickedGroup) {
                        Text("choose a group").tag(Int?.none)
                        ForEach(groups) { g in Text("\(g.name) · \(g.members.count)").tag(Int?.some(g.id)) }
                    }
                    Button("Share with the group") { Task { await share(groupID: pickedGroup) } }
                        .font(.subheadline.weight(.semibold))
                        .disabled(busy || pickedGroup == nil)
                    Button {
                        showGroups = true
                    } label: {
                        Label("Manage groups…", systemImage: "person.3")
                    }
                } header: {
                    Text("Group share")
                } footer: {
                    Text("Everyone in the group gets the offer. Make groups and add people under Manage groups.")
                }

                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }

                Section {
                    if who.isEmpty {
                        Text("Nobody yet").foregroundStyle(.secondary).font(.subheadline)
                    }
                    ForEach(who) { w in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Label("@\(w.handle ?? w.display_name)", systemImage: "person.fill")
                                if let g = w.group {
                                    Text("via \(g)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button(w.accepted ? "Revoke" : "Withdraw", role: .destructive) {
                                Task { await revoke(w) }
                            }
                            .font(.caption.weight(.medium))
                            .disabled(busy)
                        }
                        .opacity(w.accepted ? 1 : 0.7)
                    }
                } header: {
                    Text("Who has this series")
                }

                Section {
                    Button("Delete series", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Everyone it was shared with loses those videos. The videos themselves stay in My videos.")
                }
            }
            .navigationTitle("Share “\(series.name)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) }
            }
            .confirmationDialog("Delete “\(series.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete series", role: .destructive) { Task { await deleteSeries() } }
                Button("Keep", role: .cancel) {}
            }
        }
        .sheet(isPresented: $showGroups) {
            GroupsView { await load() }
        }
        .task { await load() }
    }

    private func load() async {
        async let gs = try? DanceSagePlatform.shared.groups()
        async let all = try? DanceSagePlatform.shared.series()
        groups = await gs ?? []
        who = (await all ?? []).first { $0.id == series.id }?.shared_with ?? []
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true; error = nil
        do { try await work(); await load(); await onChanged() }
        catch { self.error = error.localizedDescription }
        busy = false
    }

    private func share(handle: String? = nil, groupID: Int? = nil) async {
        let h = handle?.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        await run {
            try await DanceSagePlatform.shared.grant(seriesID: series.id, handle: (h?.isEmpty == false) ? h : nil, groupID: groupID)
            self.handle = ""
        }
    }

    private func revoke(_ w: PlatformSeries.Who) async {
        await run { try await DanceSagePlatform.shared.revokeSeriesGrant(id: w.grant_id) }
    }

    private func deleteSeries() async {
        await run { try await DanceSagePlatform.shared.deleteSeries(id: series.id) }
        dismiss()
    }
}
