import SwiftUI

/// Who can see the videos you marked Shared.
///
/// Granting is per person, not per video — mark a clip Shared and everyone on this
/// list can see it. One list to keep straight instead of a decision per clip.
///
/// Taking someone off does not chase a file: nothing was ever handed over, so the
/// next thing they open is simply refused.
struct SharedWithView: View {
    @State private var grants: [PlatformGrant] = []
    @State private var handle = ""
    @State private var busy = false
    @State private var loading = true
    @State private var error: String?

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    addRow

                    if let error {
                        Text(error)
                            .font(.footnote).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if loading {
                        ProgressView().tint(.white).padding(.top, 30)
                    } else if grants.isEmpty {
                        empty
                    } else {
                        VStack(spacing: 10) {
                            ForEach(grants) { grant in
                                row(grant)
                            }
                        }
                    }
                }
                .padding(18)
            }
        }
        .navigationTitle("Shared with")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
        .refreshable { await load() }
    }

    private var addRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.white.opacity(0.4))
                    TextField("their handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 13).padding(.vertical, 11)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    Task { await add() }
                } label: {
                    Text("Add").font(.subheadline.bold()).foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 11)
                        .background(.orange, in: Capsule())
                }
                .disabled(busy || handle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("They need a Dance Sage account. Only videos you mark Shared become visible.")
                .font(.caption).foregroundStyle(.white.opacity(0.5))
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 34)).foregroundStyle(.white.opacity(0.3))
            Text("Nobody yet").font(.headline).foregroundStyle(.white.opacity(0.8))
            Text("Videos you mark Shared are visible only to people on this list.")
                .font(.caption).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 42)
    }

    private func row(_ grant: PlatformGrant) -> some View {
        HStack(spacing: 13) {
            Circle().fill(.white.opacity(0.12)).frame(width: 42, height: 42)
                .overlay {
                    Text(String(grant.display_name.prefix(1)).uppercased())
                        .font(.headline).foregroundStyle(.orange)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(grant.display_name.isEmpty ? "@\(grant.handle)" : grant.display_name)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text("@\(grant.handle)")
                    .font(.caption).foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button("Remove", role: .destructive) {
                Task { await revoke(grant) }
            }
            .font(.caption.weight(.medium))
            .disabled(busy)
        }
        .padding(13)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func load() async {
        do {
            grants = try await DanceSagePlatform.shared.grants()
            error = nil
        } catch { self.error = error.localizedDescription }
        loading = false
    }

    private func add() async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.grant(
                handle: handle.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "@", with: ""))
            handle = ""
            await load()
        } catch { self.error = error.localizedDescription }
        busy = false
    }

    private func revoke(_ grant: PlatformGrant) async {
        busy = true; error = nil
        do {
            try await DanceSagePlatform.shared.revoke(grantID: grant.id)
            await load()
        } catch { self.error = error.localizedDescription }
        busy = false
    }
}
