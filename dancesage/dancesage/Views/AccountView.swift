import SwiftUI

/// Create an account or sign in. One screen, because they are the same two fields
/// and making people find the other one is a needless way to lose them.
struct AccountView: View {
    enum Mode { case signUp, signIn }

    @State var mode: Mode
    @StateObject private var auth = DanceSageAuth.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var offerBiometrics = false
    @State private var serverURL = AppConfig.platformBaseURL?.absoluteString ?? ""
    @State private var showingServer = false

    private var isSignUp: Bool { mode == .signUp }

    private var canSubmit: Bool {
        !busy && email.contains("@") && password.count >= 6
            && (!isSignUp || !name.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isSignUp {
                        TextField("Your name", text: $name)
                            .textContentType(.name)
                            .autocorrectionDisabled()
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(isSignUp ? .newPassword : .password)
                } footer: {
                    Text(isSignUp
                         ? "At least six characters. Your recordings stay on this iPhone until you post one."
                         : "Welcome back.")
                }

                if let error {
                    Section { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                if let notice {
                    Section { Text(notice).font(.footnote).foregroundStyle(.green) }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() }
                            else { Text(isSignUp ? "Create account" : "Sign in").bold() }
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }

                Section {
                    Button(isSignUp ? "I already have an account"
                                    : "Create an account instead") {
                        withAnimation { mode = isSignUp ? .signIn : .signUp }
                        error = nil; notice = nil
                    }
                    .font(.subheadline)

                    if !isSignUp {
                        Button("Forgot my password") { Task { await reset() } }
                            .font(.subheadline)
                            .disabled(!email.contains("@") || busy)
                    }
                }

                Section {
                    DisclosureGroup("Server", isExpanded: $showingServer) {
                        TextField("http://192.168.0.10:8000", text: $serverURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote.monospaced())
                        Button("Save") { AppConfig.setPlatformBaseURL(serverURL) }
                            .font(.footnote)
                    }
                } footer: {
                    Text("During development this is the Mac running the server.")
                }
            }
            .navigationTitle(isSignUp ? "Join Dance Sage" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.disabled(busy)
                }
            }
            .alert("Use \(BiometricLock.shared.kindName)?", isPresented: $offerBiometrics) {
                Button("Turn on") { BiometricLock.shared.enable(); dismiss() }
                Button("Not now", role: .cancel) { BiometricLock.shared.disable(); dismiss() }
            } message: {
                Text("Unlock Dance Sage with \(BiometricLock.shared.kindName) "
                     + "instead of typing your password again.")
            }
        }
        .interactiveDismissDisabled(busy)
    }

    private func submit() async {
        busy = true; error = nil; notice = nil
        do {
            if isSignUp {
                try await auth.signUp(email: email, password: password,
                                      displayName: name.trimmingCharacters(in: .whitespaces))
            } else {
                try await auth.signIn(email: email, password: password)
            }
            if BiometricLock.shared.shouldOffer {
                BiometricLock.shared.markOffered()
                offerBiometrics = true
            } else {
                BiometricLock.shared.markUnlocked()
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }

    private func reset() async {
        busy = true; error = nil; notice = nil
        do {
            try await auth.sendPasswordReset(email: email)
            notice = "Check your email for a link to set a new password."
        } catch {
            self.error = error.localizedDescription
        }
        busy = false
    }
}
