import Foundation

/// Phase 2 — the Steward reaches you *between* sessions. Phase 1 gave the app a memory it shows when
/// you open it; FleetWatch turns that same judgment into scheduled local notifications, so a car
/// crossing into overdue (or a mileage interval projected to arrive) nudges you even with the app
/// closed. It's deliberately calm and earned: per-item reminders fire at their real due time, and a
/// single fleet "check-in" — the Steward's consolidated voice — is scheduled for the next morning
/// only when something across the garage actually warrants a look. Pure and testable; the
/// UserNotifications delivery is a thin wrapper over this plan.
public struct PlannedNotification: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
    public init(id: String, title: String, body: String, fireDate: Date) {
        self.id = id; self.title = title; self.body = body; self.fireDate = fireDate
    }
}

public enum FleetWatch {
    /// iOS keeps at most 64 pending local notifications; stay well under.
    public static let maxPending = 32
    /// The stable id of the consolidated fleet check-in, so re-syncing replaces it, never stacks.
    public static let checkInID = "fleet.checkin"
    /// A calm hour for the morning brief (local time).
    public static let checkInHour = 9

    /// The full proactive plan: per-item maintenance reminders plus, when `checkInsEnabled` and the
    /// fleet has something worth surfacing, one consolidated check-in for the next morning.
    /// Soonest-first, capped.
    public static func plan(for vehicles: [Vehicle], now: Date = .now, calendar: Calendar = .current,
                            checkInsEnabled: Bool = true) -> [PlannedNotification] {
        var out = MaintenanceReminders.upcoming(for: vehicles, now: now, calendar: calendar).map {
            PlannedNotification(id: $0.id, title: $0.title, body: $0.body, fireDate: $0.fireDate)
        }
        if checkInsEnabled, let checkIn = checkIn(for: vehicles, now: now, calendar: calendar) {
            out.append(checkIn)
        }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    /// The consolidated check-in, or nil when nothing across the fleet is worth a between-visits
    /// nudge (no overdue/due-soon service and nothing flagged to review).
    public static func checkIn(for vehicles: [Vehicle], now: Date = .now,
                               calendar: Calendar = .current) -> PlannedNotification? {
        let service = FleetHealth.serviceDue(for: vehicles, now: now, calendar: calendar)
        let review = vehicles.reduce(0) { $0 + Steward.observe($1).filter { $0.tone != .informational }.count }
            + Steward.observeFleet(vehicles).filter { $0.tone != .informational }.count

        guard service.total > 0 || review > 0 else { return nil }

        let body: String
        if let focus = FleetHealth.mostUrgentService(in: vehicles, now: now, calendar: calendar) {
            let lead: String
            switch focus.due {
            case .overdue: lead = "\(focus.vehicleName)'s \(focus.itemName.lowercased()) is overdue"
            case .dueSoon: lead = "\(focus.vehicleName)'s \(focus.itemName.lowercased()) is due soon"
            case .ok: lead = "\(focus.vehicleName) needs a look"
            }
            let others = max(0, service.total - 1)
            body = others > 0
                ? "\(lead), and \(others) other car\(others == 1 ? "" : "s") need a look."
                : "\(lead)."
        } else {
            body = "\(review) thing\(review == 1 ? "" : "s") across the garage worth a look."
        }

        return PlannedNotification(id: checkInID, title: "Steward check-in",
                                   body: body, fireDate: nextCheckIn(after: now, calendar: calendar))
    }

    /// The next occurrence of the calm check-in hour, strictly in the future.
    public static func nextCheckIn(after now: Date, calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = checkInHour; comps.minute = 0; comps.second = 0
        let todayAtHour = calendar.date(from: comps) ?? now
        if todayAtHour > now.addingTimeInterval(300) { return todayAtHour }   // 5-min guard against "just now"
        return calendar.date(byAdding: .day, value: 1, to: todayAtHour) ?? now.addingTimeInterval(86_400)
    }
}

/// Owner preference for between-visit check-ins (the per-item due reminders always follow the OS
/// notification permission). Default on.
public enum FleetWatchSettings {
    private static let key = "GarageHUD.stewardCheckIns.enabled"
    public static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }
    public static func setEnabled(_ value: Bool, _ defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: key)
    }
}
