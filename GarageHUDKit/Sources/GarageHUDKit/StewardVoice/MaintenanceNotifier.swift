import Foundation

#if canImport(UserNotifications)
@preconcurrency import UserNotifications

/// Delivers `MaintenanceReminders` as local notifications. Thin over the pure scheduling logic:
/// it asks permission once, then mirrors the computed reminder set into the notification center,
/// replacing the app's previous maintenance requests so nothing duplicates or goes stale.
///
/// EXPERIMENTAL on device: the scheduling logic is unit-tested, but actual delivery needs a run
/// on hardware with notifications allowed.
public enum MaintenanceNotifier {
    private static let prefix = "maint."

    /// Ask for permission (once; the system remembers the choice). Safe to call repeatedly.
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Replace all pending maintenance notifications with the current computed set.
    public static func sync(for vehicles: [Vehicle], now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)

            for reminder in MaintenanceReminders.upcoming(for: vehicles, now: now) {
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                // Fire at the reminder's date (never in the past).
                let interval = max(60, reminder.fireDate.timeIntervalSince(now))
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
            }
        }
    }
}
#endif
