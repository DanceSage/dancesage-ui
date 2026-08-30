import Foundation

enum AppConfig {
    /// Event discovery needs the DanceSage API hosted and hardened. Hidden for the
    /// initial App Store release; flip back on when the server ships.
    static let discoveryEnabled = false

    /// Publishing to a profile. Off until the platform is deployed — with it off the
    /// app is exactly what it is today: everything on device, no account, no network.
    static let platformEnabled = true

    /// Firebase is the identity layer. This key is public by design — it identifies
    /// the project and grants nothing; access is controlled by rules and by the
    /// server verifying every token.
    static let firebaseAPIKey = "AIzaSyAADqm7zIzG4q2qnez2fFOphp42W3-OhIc"

    /// Where the platform lives. During development this is a Mac on the same wifi,
    /// so it is overridable at runtime rather than baked in — LAN addresses change.
    static var platformBaseURL: URL? {
        if let override = UserDefaults.standard.string(forKey: "ds.platformBaseURL"),
           let url = URL(string: override), !isUnreachableLAN(url) {
            return url
        }
        return URL(string: defaultPlatformBaseURL)
    }

    /// An address on somebody's home network, saved back when the server lived on
    /// a desk. It works on that wifi and nowhere else, so honouring it now would
    /// mean the app quietly stops working the moment you leave the house.
    private static func isUnreachableLAN(_ url: URL) -> Bool {
        guard let host = url.host else { return true }
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }        // a hostname, not an IP
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168):        return true
        case (172, 16...31):                       return true
        case (169, 254):                           return true
        default:                                   return false
        }
    }

    static func setPlatformBaseURL(_ value: String?) {
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: "ds.platformBaseURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "ds.platformBaseURL")
        }
    }

    /// The deployed platform, in every build.
    ///
    /// Debug used to point at a Mac on the wifi, which worked at the desk and
    /// hung forever on cellular — a private address is unreachable from anywhere
    /// else, and the request just waits. Now that the server is deployed there is
    /// no reason to prefer the laptop; override it in Settings when working on
    /// the server itself.
    private static let defaultPlatformBaseURL = "https://dancesage.com"
}
