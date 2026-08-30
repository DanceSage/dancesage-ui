import Foundation
import Combine
import Security

/// Sign-in for the Dance Sage platform.
///
/// Firebase is the identity layer, but the app talks to its REST endpoint rather than
/// linking the Firebase SDK — email and password is one request, and Sign in with Apple
/// will be `ASAuthorization` handing a token to the same exchange. Nothing extra ships
/// in the binary, and there is no SDK to keep updated.
///
/// Two tokens are involved and it matters which is which:
///   • Firebase ID token — proves who you are to *us*, used once, then discarded
///   • Dance Sage session — what every later request carries, kept in the Keychain
enum DanceSageAuthError: LocalizedError {
    case notConfigured
    case badCredentials
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Dance Sage server is not configured."
        case .badCredentials: return "Wrong email or password."
        case .server(let m): return m
        }
    }
}

@MainActor
final class DanceSageAuth: ObservableObject {
    static let shared = DanceSageAuth()

    @Published private(set) var handle: String?
    @Published private(set) var displayName: String?
    @Published private(set) var needsHandle = false

    private let keychainKey = "ds.session.token"
    private let firebaseKey = AppConfig.firebaseAPIKey
    private let session: URLSession

    init(session: URLSession? = nil) {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        c.waitsForConnectivity = false
        self.session = session ?? URLSession(configuration: c)
        self.handle = UserDefaults.standard.string(forKey: "ds.handle")
        self.displayName = UserDefaults.standard.string(forKey: "ds.displayName")
    }

    var isSignedIn: Bool { sessionToken != nil }

    /// The token every authenticated request carries.
    var sessionToken: String? {
        get { Keychain.read(keychainKey) }
        set { newValue.map { Keychain.write(keychainKey, $0) } ?? Keychain.delete(keychainKey) }
    }

    // MARK: - Sign in

    func signIn(email: String, password: String) async throws {
        let idToken = try await firebaseSignIn(email: email, password: password)
        try await exchange(idToken: idToken, displayName: nil)
    }

    /// Create an account. Firebase makes the identity; the exchange makes the profile.
    func signUp(email: String, password: String, displayName: String?) async throws {
        let idToken = try await firebaseCall("accounts:signUp",
                                             email: email, password: password)
        try await exchange(idToken: idToken, displayName: displayName)
    }

    /// Sends the reset mail. Firebase handles the rest; we never see the password.
    func sendPasswordReset(email: String) async throws {
        guard !firebaseKey.isEmpty,
              let url = URL(string: "https://identitytoolkit.googleapis.com/v1/"
                            + "accounts:sendOobCode?key=\(firebaseKey)")
        else { throw DanceSageAuthError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "requestType": "PASSWORD_RESET", "email": email])
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DanceSageAuthError.server(Self.firebaseMessage(data)
                ?? "Could not send the reset email.")
        }
    }

    /// Sign in with Apple hands us a token from `ASAuthorization`; the exchange is identical.
    func signIn(appleIdentityToken: String, displayName: String?) async throws {
        try await exchange(idToken: appleIdentityToken, displayName: displayName)
    }

    /// Called once a handle has been chosen, so the gate stops asking.
    func handleChosen(_ handle: String) {
        self.handle = handle
        needsHandle = false
        UserDefaults.standard.set(handle, forKey: "ds.handle")
    }

    /// Delete the account, everywhere.
    ///
    /// Two systems hold something: Dance Sage holds the profile and the posts,
    /// Firebase holds the identity. The server cannot remove the second — it never
    /// has a credential for it — so the app asks for the password again, which both
    /// proves it is really you and produces the token Firebase needs.
    ///
    /// Dance Sage goes first. If Firebase then fails, the person has lost their
    /// data and kept an unusable login, which they can retry. The other order could
    /// leave an identity with no account behind it and no way back in to finish.
    func deleteAccount(email: String, password: String) async throws {
        let idToken = try await firebaseSignIn(email: email, password: password)

        guard let base = AppConfig.platformBaseURL, let token = sessionToken else {
            throw DanceSageAuthError.notConfigured
        }
        var req = URLRequest(url: base.appendingPathComponent("v1/me"))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                .flatMap { $0["detail"] as? String }
            throw DanceSageAuthError.server(detail ?? "Could not delete your Dance Sage account.")
        }

        try await deleteFirebaseIdentity(idToken: idToken)
        signOut()
    }

    private func deleteFirebaseIdentity(idToken: String) async throws {
        guard !firebaseKey.isEmpty,
              let url = URL(string: "https://identitytoolkit.googleapis.com/v1/"
                            + "accounts:delete?key=\(firebaseKey)")
        else { throw DanceSageAuthError.notConfigured }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["idToken": idToken])
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw DanceSageAuthError.server(
                Self.firebaseMessage(data)
                ?? "Your videos were deleted, but the sign-in could not be removed. "
                 + "Contact hello@dancesage.com.")
        }
    }

    func signOut() {
        sessionToken = nil
        handle = nil
        displayName = nil
        needsHandle = false
        UserDefaults.standard.removeObject(forKey: "ds.handle")
        UserDefaults.standard.removeObject(forKey: "ds.displayName")
    }

    // MARK: - Steps

    private func firebaseSignIn(email: String, password: String) async throws -> String {
        try await firebaseCall("accounts:signInWithPassword",
                               email: email, password: password)
    }

    /// Sign-in and sign-up differ only in the endpoint, so they share the request.
    private func firebaseCall(_ endpoint: String, email: String,
                              password: String) async throws -> String {
        guard !firebaseKey.isEmpty,
              let url = URL(string: "https://identitytoolkit.googleapis.com/v1/"
                            + "\(endpoint)?key=\(firebaseKey)")
        else { throw DanceSageAuthError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email, "password": password, "returnSecureToken": true
        ])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw DanceSageAuthError.server("No response from sign-in.")
        }
        guard http.statusCode == 200 else {
            // Firebase says what actually went wrong; a blanket "wrong password"
            // on an already-registered email would send people in circles.
            if let message = Self.firebaseMessage(data) {
                throw DanceSageAuthError.server(message)
            }
            throw DanceSageAuthError.badCredentials
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["idToken"] as? String else {
            throw DanceSageAuthError.server("Sign-in response was not understood.")
        }
        return idToken
    }

    private func exchange(idToken: String, displayName: String?) async throws {
        guard let base = AppConfig.platformBaseURL else { throw DanceSageAuthError.notConfigured }
        var req = URLRequest(url: base.appendingPathComponent("v1/auth/signin"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["idToken": idToken]
        if let displayName { body["displayName"] = displayName }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?
                .flatMap { $0["detail"] as? String }
            throw DanceSageAuthError.server(detail ?? "Could not reach Dance Sage.")
        }

        sessionToken = token
        needsHandle = json["needs_handle"] as? Bool ?? false
        if let me = json["me"] as? [String: Any] {
            handle = (me["handle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            displayName.map { self.displayName = $0 }
            if self.displayName == nil { self.displayName = me["display_name"] as? String }
            UserDefaults.standard.set(handle, forKey: "ds.handle")
            UserDefaults.standard.set(self.displayName, forKey: "ds.displayName")
        }
    }
}

extension DanceSageAuth {
    /// Firebase's error codes, in words a person can act on.
    static func firebaseMessage(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let code = error["message"] as? String else { return nil }
        switch code.components(separatedBy: " :").first ?? code {
        case "EMAIL_EXISTS":
            return "That email already has an account. Sign in instead."
        case "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD", "EMAIL_NOT_FOUND":
            return "Wrong email or password."
        case "WEAK_PASSWORD": 
            return "Use at least six characters."
        case "INVALID_EMAIL":
            return "That does not look like an email address."
        case "TOO_MANY_ATTEMPTS_TRY_LATER":
            return "Too many attempts. Wait a moment and try again."
        default:
            return nil
        }
    }
}

// MARK: - Keychain

/// Session tokens belong in the Keychain, not UserDefaults — it survives reinstall
/// only if we want it to, and it is not readable from a device backup in plain text.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.dancesage",
         kSecAttrAccount as String: key]
    }

    static func read(_ key: String) -> String? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        delete(key)
        var q = query(key)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }

    static func delete(_ key: String) {
        SecItemDelete(query(key) as CFDictionary)
    }
}
