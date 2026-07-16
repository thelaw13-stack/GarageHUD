import Foundation

/// Decides — and remembers — whether to nudge the owner toward a better Steward voice.
///
/// The nudge earns its place only when it's actually useful: the device has just the robotic system
/// default installed, *and* the natural cloud voice is off (so the on-device quality is what they'll
/// hear), *and* they haven't already waved it away. Dismissal is sticky, so it never nags. The
/// decision is pure so it can be unit-tested without a device or a speech synthesizer.
public enum VoiceNudge {
    private static let dismissedKey = "GarageHUD.betterVoiceNudgeDismissed.v1"

    /// Show the nudge only when a better voice would genuinely help and the owner hasn't dismissed it.
    public static func shouldShow(onlyDefaultVoiceInstalled: Bool,
                                  cloudVoiceEnabled: Bool,
                                  dismissed: Bool) -> Bool {
        onlyDefaultVoiceInstalled && !cloudVoiceEnabled && !dismissed
    }

    public static func isDismissed(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: dismissedKey)
    }

    public static func markDismissed(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: dismissedKey)
    }
}
