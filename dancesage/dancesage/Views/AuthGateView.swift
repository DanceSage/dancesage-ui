import SwiftUI

/// The front door. No account, no app.
///
/// The check is against the session in the Keychain, never the network — so the app
/// opens on a plane, in a basement studio, or with the server down. Signing in is the
/// only thing that needs a connection; everything after it does not.
struct AuthGateView: View {
    @ObservedObject private var auth = DanceSageAuth.shared
    @ObservedObject private var lock = BiometricLock.shared

    var body: some View {
        Group {
            if !auth.isSignedIn {
                WelcomeView()
            } else if lock.isLocked {
                LockedView()
            } else if auth.needsHandle || (auth.handle ?? "").isEmpty {
                // Sharing works by handle, so an account without one is unreachable.
                ChooseHandleView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: auth.isSignedIn)
    }
}

/// What someone sees before they have an account.
private struct WelcomeView: View {
    @State private var showAuth = false
    @State private var mode: AccountView.Mode = .signUp

    private let background = Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            Circle().fill(.orange.opacity(0.18)).frame(width: 250, height: 250)
                .blur(radius: 70).offset(x: 170, y: -310)
            Circle().fill(.green.opacity(0.14)).frame(width: 260, height: 260)
                .blur(radius: 70).offset(x: -170, y: 300)

            VStack(spacing: 0) {
                Spacer()
                Image("AppLogo")
                    .resizable().scaledToFit()
                    .frame(width: 116, height: 116)
                    .accessibilityHidden(true)

                Text("Dance Sage")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 18)
                Text("Record a move. The AI turns it into a lesson.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
                    .padding(.horizontal, 34)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        mode = .signUp; showAuth = true
                    } label: {
                        Text("Create account")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.orange, in: Capsule())
                    }
                    Button {
                        mode = .signIn; showAuth = true
                    } label: {
                        Text("I already have one")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(.white.opacity(0.10), in: Capsule())
                    }
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 34)
            }
        }
        .sheet(isPresented: $showAuth) { AccountView(mode: mode) }
    }
}

/// A session exists, but this launch has not proved who is holding the phone.
private struct LockedView: View {
    @ObservedObject private var auth = DanceSageAuth.shared
    @ObservedObject private var lock = BiometricLock.shared

    var body: some View {
        ZStack {
            Color(red: 81 / 255, green: 63 / 255, blue: 89 / 255).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 54)).foregroundStyle(.orange)
                Text("Locked").font(.title3.bold()).foregroundStyle(.white)
                Text("Unlock with \(lock.kindName) to open Dance Sage.")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.66))
                    .multilineTextAlignment(.center)
                Button("Unlock") { Task { _ = await lock.unlock() } }
                    .font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 34).padding(.vertical, 13)
                    .background(.orange, in: Capsule())
                Button("Sign out") { auth.signOut() }
                    .font(.footnote).foregroundStyle(.white.opacity(0.5))
            }
            .padding(34)
        }
        .task { _ = await lock.unlock() }
    }
}
