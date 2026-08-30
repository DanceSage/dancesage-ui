import SwiftUI

/// Pick the name people will use to find and share with you.
///
/// Asked once, straight after signing up. Sharing works by handle, so an account
/// without one cannot be shared with — which makes this the last step of joining
/// rather than a setting somebody might never open.
struct ChooseHandleView: View {
    @ObservedObject private var auth = DanceSageAuth.shared

    @State private var handle = ""
    @State private var status: DanceSagePlatform.HandleCheck?
    @State private var checking = false
    @State private var saving = false
    @State private var error: String?
    @State private var check: Task<Void, Never>?

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    private var cleaned: String {
        handle.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                Text("Pick your handle")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text("This is how people find you and share moves with you.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6).padding(.horizontal, 30)

                HStack(spacing: 3) {
                    Text("@").font(.title3.bold()).foregroundStyle(.white.opacity(0.4))
                    TextField("", text: $handle, prompt: Text("yourname")
                        .foregroundStyle(.white.opacity(0.3)))
                        .font(.title3.weight(.semibold))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(borderColour, lineWidth: 1)
                }
                .padding(.horizontal, 30).padding(.top, 26)

                // Says what will happen before it happens.
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageColour)
                    .frame(height: 18)
                    .padding(.top, 8)

                Spacer()

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if saving { ProgressView().tint(.black) }
                        else { Text("Continue").font(.headline).foregroundStyle(.black) }
                        Spacer()
                    }
                    .padding(.vertical, 15)
                    .background(.orange, in: Capsule())
                }
                .disabled(!(status?.ok ?? false) || saving)
                .opacity((status?.ok ?? false) ? 1 : 0.45)
                .padding(.horizontal, 30)

                Button("Sign out") { auth.signOut() }
                    .font(.footnote).foregroundStyle(.white.opacity(0.45))
                    .padding(.top, 14).padding(.bottom, 30)
            }
        }
        .onChange(of: handle) { _, _ in schedule() }
    }

    private var borderColour: Color {
        guard let status, !cleaned.isEmpty else { return .white.opacity(0.12) }
        return status.ok ? .green.opacity(0.7) : .red.opacity(0.6)
    }
    private var message: String {
        if let error { return error }
        if cleaned.isEmpty { return "dancesage.com/@\(cleaned.isEmpty ? "yourname" : cleaned)" }
        if checking { return "Checking…" }
        guard let status else { return " " }
        return status.ok ? "dancesage.com/@\(cleaned) is yours" : status.why
    }
    private var messageColour: Color {
        if error != nil { return .red }
        guard let status, !cleaned.isEmpty, !checking else { return .white.opacity(0.4) }
        return status.ok ? .green : .red
    }

    private func schedule() {
        error = nil
        check?.cancel()
        guard cleaned.count >= 3 else { status = nil; checking = false; return }
        checking = true
        check = Task {
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            status = try? await DanceSagePlatform.shared.handleAvailable(cleaned)
            checking = false
        }
    }

    private func save() async {
        saving = true; error = nil
        do {
            try await DanceSagePlatform.shared.setHandle(cleaned)
            auth.handleChosen(cleaned)
        } catch {
            self.error = error.localizedDescription
        }
        saving = false
    }
}
