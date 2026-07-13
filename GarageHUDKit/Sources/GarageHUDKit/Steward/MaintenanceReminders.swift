import Foundation

/// A scheduled reminder for a maintenance item — the pure description of *what* to notify and
/// *when*. Delivery (local notifications) is a thin platform layer over this; the decision of
/// what to schedule lives here so it's testable without the notification system.
public struct MaintenanceReminder: Identifiable, Equatable, Sendable {
    /// Stable per (vehicle, item) so rescheduling replaces rather than duplicates.
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date
}

public enum MaintenanceReminders {
    /// iOS keeps at most 64 pending local notifications; stay well under.
    public static let maxPending = 32

    /// The reminders to schedule for a fleet: one per maintenance item, firing at its due date —
    /// or shortly from now if it's already overdue (so the owner still gets nudged). Soonest
    /// first, capped. A car that's out of service is skipped (you're not driving it).
    public static func upcoming(for vehicles: [Vehicle], now: Date = .now,
                                calendar: Calendar = .current) -> [MaintenanceReminder] {
        var reminders: [MaintenanceReminder] = []
        for vehicle in vehicles where !vehicle.serviceStatus.isInService {
            let odo = vehicle.currentMileage
            let rate = vehicle.milesPerDay
            for item in vehicle.maintenance {
                let timeDue = item.dueDate(calendar)
                let milesRemaining = item.milesUntilDue(currentMileage: odo)
                let mileOverdue = (milesRemaining ?? .max) <= 0
                // With a learned driving rate we can project a real fire date for a future mileage
                // interval; otherwise mileage can only nudge once it's already overdue.
                let expected = item.expectedDueDate(currentMileage: odo, milesPerDay: rate,
                                                    now: now, calendar: calendar)
                let overdue = now >= timeDue || mileOverdue
                let fire = overdue ? now.addingTimeInterval(60) : max(expected, now.addingTimeInterval(60))
                let body: String
                if mileOverdue, let target = item.dueMileage {
                    body = "Overdue — due at \(target.formatted(.number.grouping(.automatic))) mi."
                } else if overdue {
                    body = "Overdue — last done \(short(item.lastServiced, calendar)) on a \(item.intervalMonths)-month interval."
                } else if expected < timeDue, let remaining = milesRemaining {
                    // Mileage projection beats the calendar — say so in miles.
                    body = "Projected in ~\(remaining.formatted(.number.grouping(.automatic))) mi (\(short(expected, calendar)))."
                } else {
                    body = "Due \(short(timeDue, calendar))."
                }
                reminders.append(MaintenanceReminder(
                    id: "maint.\(vehicle.id.uuidString).\(item.id.uuidString)",
                    title: "\(vehicle.displayName): \(item.name)",
                    body: body,
                    fireDate: fire))
            }
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    private static func short(_ date: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter(); f.calendar = calendar; f.dateStyle = .medium
        return f.string(from: date)
    }
}
