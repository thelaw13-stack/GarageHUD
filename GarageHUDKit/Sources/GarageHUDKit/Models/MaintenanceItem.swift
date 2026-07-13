import Foundation

/// A recurring maintenance item. Always on a date interval (works for any car, no odometer
/// required); optionally *also* on a mileage interval (oil every 5,000 mi), in which case whichever
/// comes first — time or miles — drives the due state, the way a shop schedule actually works.
public struct MaintenanceItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var intervalMonths: Int
    public var lastServiced: Date
    public var note: String = ""
    /// Optional mileage interval. When set (with `lastServicedMileage`), the item also comes due
    /// after this many miles since it was last serviced.
    public var intervalMiles: Int? = nil
    /// The odometer at the last service — the baseline the mileage interval counts from.
    public var lastServicedMileage: Int? = nil

    public init(id: UUID = UUID(), name: String, intervalMonths: Int, lastServiced: Date,
                note: String = "", intervalMiles: Int? = nil, lastServicedMileage: Int? = nil) {
        self.id = id
        self.name = name
        self.intervalMonths = intervalMonths
        self.lastServiced = lastServiced
        self.note = note
        self.intervalMiles = intervalMiles
        self.lastServicedMileage = lastServicedMileage
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        intervalMonths = try c.decodeIfPresent(Int.self, forKey: .intervalMonths) ?? 6
        lastServiced = try c.decodeIfPresent(Date.self, forKey: .lastServiced) ?? .now
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        intervalMiles = try c.decodeIfPresent(Int.self, forKey: .intervalMiles)
        lastServicedMileage = try c.decodeIfPresent(Int.self, forKey: .lastServicedMileage)
    }

    public enum Due: Sendable, Equatable { case ok, dueSoon, overdue }

    public func dueDate(_ calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: intervalMonths, to: lastServiced) ?? lastServiced
    }

    /// The odometer this item next comes due at, if a mileage interval is configured.
    public var dueMileage: Int? {
        guard let interval = intervalMiles, interval > 0, let base = lastServicedMileage else { return nil }
        return base + interval
    }

    /// Miles remaining until the mileage interval is up (negative = past due), or nil if there's no
    /// mileage interval or no current odometer to measure against.
    public func milesUntilDue(currentMileage: Int?) -> Int? {
        guard let target = dueMileage, let odo = currentMileage else { return nil }
        return target - odo
    }

    /// When the mileage interval is projected to come due, given a driving rate (miles/day). Uses
    /// the miles remaining and the rate to convert distance into a calendar date. Already-overdue
    /// returns `now`. Nil when there's no mileage interval, no current odometer, or no rate.
    public func projectedMileageDueDate(currentMileage: Int?, milesPerDay: Double?,
                                        now: Date = .now) -> Date? {
        guard let remaining = milesUntilDue(currentMileage: currentMileage) else { return nil }
        if remaining <= 0 { return now }
        guard let rate = milesPerDay, rate > 0 else { return nil }
        return now.addingTimeInterval(Double(remaining) / rate * 86_400)
    }

    /// The soonest this item is expected to come due — the earlier of its time interval and its
    /// projected mileage date (when a rate is known). This is the honest "next due" for scheduling.
    public func expectedDueDate(currentMileage: Int?, milesPerDay: Double?,
                                now: Date = .now, calendar: Calendar = .current) -> Date {
        let timeDue = dueDate(calendar)
        guard let mileDue = projectedMileageDueDate(currentMileage: currentMileage,
                                                    milesPerDay: milesPerDay, now: now) else { return timeDue }
        return min(timeDue, mileDue)
    }

    /// Time-only due state. `dueSoon` within 30 days of the due date; `overdue` once passed.
    public func due(now: Date = .now, calendar: Calendar = .current) -> Due {
        let due = dueDate(calendar)
        if now >= due { return .overdue }
        let days = calendar.dateComponents([.day], from: now, to: due).day ?? .max
        return days <= 30 ? .dueSoon : .ok
    }

    /// Combined due state: the more urgent of the time interval and the mileage interval (if any).
    /// Mileage is `dueSoon` within 500 mi of the target, `overdue` once reached.
    public func due(now: Date = .now, calendar: Calendar = .current, currentMileage: Int?) -> Due {
        var states = [due(now: now, calendar: calendar)]
        if let remaining = milesUntilDue(currentMileage: currentMileage) {
            states.append(remaining <= 0 ? .overdue : (remaining <= 500 ? .dueSoon : .ok))
        }
        if states.contains(.overdue) { return .overdue }
        if states.contains(.dueSoon) { return .dueSoon }
        return .ok
    }
}
