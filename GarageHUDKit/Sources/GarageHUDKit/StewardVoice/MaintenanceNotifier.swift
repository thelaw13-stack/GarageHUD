import Foundation

#if canImport(UserNotifications)
@preconcurrency import UserNotifications

/// Delivers the `FleetWatch` plan — per-item maintenance reminders plus the consolidated fleet
/// check-in — as local notifications, so the Steward reaches the owner between sessions. Thin over
/// the pure scheduling logic: it asks permission once, then mirrors the computed plan into the
/// notification center, replacing the app's previous requests so nothing duplicates or goes stale.
///
/// EXPERIMENTAL on device: the scheduling logic is unit-tested, but actual delivery needs a run
/// on hardware with notifications allowed.
public enum MaintenanceNotifier {
    /// Our identifiers: `maint.*` (per item) and the single `fleet.checkin`.
    private static func isOurs(_ id: String) -> Bool { id.hasPrefix("maint.") || id == FleetWatch.checkInID }

    /// Ask for permission (once; the system remembers the choice). Safe to call repeatedly.
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replace all pending Steward notifications with the current computed plan.
    public static func sync(for vehicles: [Vehicle], now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        let plan = FleetWatch.plan(for: vehicles, now: now, checkInsEnabled: FleetWatchSettings.isEnabled())
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter(isOurs)
            center.removePendingNotificationRequests(withIdentifiers: ours)

            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                // Fire at the planned date (never in the past).
                let interval = max(60, item.fireDate.timeIntervalSince(now))
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}
#endif
