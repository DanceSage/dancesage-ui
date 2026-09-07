import Foundation

/// Where this account's library lives on the phone.
///
/// Recordings, lessons and attempts stay on the device — that is the privacy
/// story — but they belong to the person signed in, not to the phone. Every
/// account gets its own folder, keyed by the platform's user id from the
/// session, so signing in as someone else on the same iPhone shows their
/// library, empty or not, and never yours.
///
/// The folder is one the app made itself. A library put back by a tool from
/// outside the app arrives owned by someone else, and then nothing under it
/// can be written or even re-permissioned; so anything found in the old
/// places is copied in — reading is always allowed — and dropped where it can be.
@MainActor
enum AccountScope {
    private static let fileManager = FileManager.default
    private static var adoptedFor: String?

    /// `…/DanceSage Library/<account>/`, created on demand.
    static func directory() throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let key = accountKey()
        let directory = support
            .appendingPathComponent("DanceSage Library", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if adoptedFor != key {
            adoptedFor = key
            let old = support.appendingPathComponent("DanceSage", isDirectory: true)
            adopt(from: old.appendingPathComponent("accounts", isDirectory: true)
                            .appendingPathComponent(key, isDirectory: true), into: directory)
            adopt(from: old, into: directory)    // the pre-folder, per-phone library
        }
        return directory
    }

    /// The platform's user id, read from the session token. The handle can
    /// change; the id cannot. Without a session — which the sign-in gate
    /// should make impossible — the library is simply "local".
    private static func accountKey() -> String {
        guard let token = DanceSageAuth.shared.sessionToken,
              let uid = jwtClaim("uid", in: token) else { return "local" }
        return "user-\(uid)"
    }

    private static func jwtClaim(_ name: String, in token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json[name] else { return nil }
        return "\(value)"
    }

    /// Copies a library's four parts into this account, skipping what the
    /// account already has, then drops the source if it can.
    private static func adopt(from source: URL, into directory: URL) {
        guard fileManager.fileExists(atPath: source.path) else { return }
        for name in ["recordings.json", "lessons.json", "Videos", "Attempts"] {
            let old = source.appendingPathComponent(name)
            let new = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: old.path) else { continue }
            if !fileManager.fileExists(atPath: new.path) {
                try? fileManager.copyItem(at: old, to: new)
            }
            try? fileManager.removeItem(at: old)
        }
    }
}
