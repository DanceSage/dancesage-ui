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
           let url = URL(string: override) {
            return url
        }
        return URL(string: defaultPlatformBaseURL)
    }

    static func setPlatformBaseURL(_ value: String?) {
        if let value, !value.isEmpty {
            UserDefaults.standard.set(value, forKey: "ds.platformBaseURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "ds.platformBaseURL")
        }
    }

    #if DEBUG
    /// Set this to the Mac running `uvicorn`, then override in Settings if it moves.
    private static let defaultPlatformBaseURL = "http://10.1.1.188:8000"
    #else
    private static let defaultPlatformBaseURL = "https://dancesage.com"
    #endif
}
