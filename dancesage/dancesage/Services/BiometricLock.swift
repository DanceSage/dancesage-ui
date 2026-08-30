import Foundation
import Combine
import LocalAuthentication

/// Face ID over the stored session.
///
/// This is separate from signing in. You sign in once with whatever provider, the
/// session goes to the Keychain, and from then on Face ID is what unlocks it — so
/// the provider never matters to this file.
@MainActor
final class BiometricLock: ObservableObject {
    static let shared = BiometricLock()

    private let enabledKey = "ds.biometricEnabled"
    private let askedKey = "ds.biometricAsked"

    @Published private(set) var isUnlocked = false

    /// Face ID, Touch ID, or nothing on this device.
    var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                             error: &error)
    }

    var kindName: String {
        switch LAContext().biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "biometrics"
        }
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Offer it once, after the first successful sign-in.
    var shouldOffer: Bool {
        available && !isEnabled && !UserDefaults.standard.bool(forKey: askedKey)
    }

    func markOffered() { UserDefaults.standard.set(true, forKey: askedKey) }

    func enable() { isEnabled = true; markOffered(); isUnlocked = true }

    func disable() { isEnabled = false; isUnlocked = true }

    /// Just signed in with a password, so the session is already earned.
    func markUnlocked() { isUnlocked = true }

    /// A stored session that has not been unlocked this launch.
    var isLocked: Bool { isEnabled && available && !isUnlocked }

    /// Called on launch when a session exists and the lock is on.
    func unlock() async -> Bool {
        guard isEnabled, available else { isUnlocked = true; return true }
        let context = LAContext()
        context.localizedFallbackTitle = "Use password"
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your Dance Sage profile")
            isUnlocked = ok
            return ok
        } catch {
            isUnlocked = false
            return false
        }
    }

    func relock() { if isEnabled { isUnlocked = false } }
}
