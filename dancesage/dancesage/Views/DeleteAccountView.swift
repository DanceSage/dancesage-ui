import SwiftUI

/// Deleting your account.
///
/// Apple requires this of any app that creates accounts, and it has to be
/// reachable — not an email you send to support. It says exactly what goes,
/// asks for the password so nobody can do it to a phone left on a table, and
/// makes you type the word rather than tap a button you might tap by accident.
struct DeleteAccountView: View {
    @ObservedObject private var auth = DanceSageAuth.shared
    @Environment(\.dismiss) private var dismiss

    let postCount: Int

    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var canDelete: Bool {
        !busy && email.contains("@") && !password.isEmpty
            && confirm.trimmingCharacters(in: .whitespaces).uppercased() == "DELETE"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("This cannot be undone", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.subheadline.weight(.semibold))
                } footer: {
                    Text("Deleting your account removes:")
                }

                Section {
                    row("person.crop.circle", "Your profile and handle")
                    row("play.rectangle.on.rectangle",
                        postCount == 1 ? "1 posted video, and its skeleton"
                                       : "\(postCount) posted videos, and their skeletons")
                    row("person.2", "Everyone you shared with, and everything shared with you")
                    row("key", "Your sign-in")
                } footer: {
                    Text("Recordings saved on this iPhone are not deleted. "
                         + "Remove the app to clear those.")
                }

                Section {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Confirm it is you")
                } footer: {
                    Text("Your password is needed to delete the sign-in itself.")
                }

                Section {
                    TextField("Type DELETE", text: $confirm)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }

                Section {
                    Button(role: .destructive) {
                        Task { await delete() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() }
                            else { Text("Delete my account").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canDelete)
                }
            }
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.primary)
    }

    private func delete() async {
        busy = true; error = nil
        do {
            try await auth.deleteAccount(email: email, password: password)
            // The gate notices there is no session and shows the welcome screen.
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
