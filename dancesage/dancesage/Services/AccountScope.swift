import Foundation

/// Where this account's library lives on the phone.
///
/// Recordings, lessons and attempts stay on the device — that is the privacy
/// story — but they belong to the person signed in, not to the phone. Every
/// account gets its own folder, keyed by the platform's user id from the
/// session, so signing in as someone else on the same iPhone shows their
/// library, empty or not, and never yours.
///
/// A library written before folders existed belongs to whoever was signed in
/// when it was made — the phone's owner. It moves into the first account that
/// opens the app after the change, once.
@MainActor
enum AccountScope {
    private static let fileManager = FileManager.default
    private static var migratedFor: String?

    /// `…/DanceSage/accounts/<uid>/`, created on demand.
    static func directory() throws -> URL {
        let root = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("DanceSage", isDirectory: true)
        let key = accountKey()
        let directory = root
            .appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        if migratedFor != key {
            migratedFor = key
            adoptDeviceLibrary(at: root, into: directory)
            ensureWritable(root.appendingPathComponent("accounts", isDirectory: true))
        }
        return directory
    }

    /// A library restored from outside the app can arrive read-only. If a
    /// probe write fails, put the permissions back to the app's own.
    private static func ensureWritable(_ directory: URL) {
        let probe = directory.appendingPathComponent(".probe")
        if (try? Data().write(to: probe)) != nil {
            try? fileManager.removeItem(at: probe)
            return
        }
        guard let walk = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        for case let url as URL in walk {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            try? fileManager.setAttributes([.posixPermissions: isDir ? 0o755 : 0o644], ofItemAtPath: url.path)
        }
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

    /// The pre-folder library (`recordings.json`, `lessons.json`, `Videos/`,
    /// `Attempts/`) sits directly under DanceSage/. Move it into this account,
    /// leaving nothing behind for the next person to inherit.
    private static func adoptDeviceLibrary(at root: URL, into directory: URL) {
        for name in ["recordings.json", "lessons.json", "Videos", "Attempts"] {
            let old = root.appendingPathComponent(name)
            let new = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: old.path) else { continue }
            if fileManager.fileExists(atPath: new.path) {
                // The account already has one; the old copy is a duplicate now.
                try? fileManager.removeItem(at: old)
            } else {
                try? fileManager.moveItem(at: old, to: new)
            }
        }
    }
}
