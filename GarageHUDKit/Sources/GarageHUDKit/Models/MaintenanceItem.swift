import Foundation

/// A recurring maintenance item on a date interval (oil, fluids, filters…). Kept date-based —
/// no odometer required — so it works for any car in the fleet, including a daily driver.
public struct MaintenanceItem: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var intervalMonths: Int
    public var lastServiced: Date
    public var note: String = ""

    public init(id: UUID = UUID(), name: String, intervalMonths: Int, lastServiced: Date, note: String = "") {
        self.id = id
        self.name = name
        self.intervalMonths = intervalMonths
        self.lastServiced = lastServiced
        self.note = note
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        intervalMonths = try c.decodeIfPresent(Int.self, forKey: .intervalMonths) ?? 6
        lastServiced = try c.decodeIfPresent(Date.self, forKey: .lastServiced) ?? .now
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    public enum Due: Sendable, Equatable { case ok, dueSoon, overdue }

    public func dueDate(_ calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: intervalMonths, to: lastServiced) ?? lastServiced
    }

    /// `dueSoon` fires within 30 days of the due date; `overdue` once it's passed.
    public func due(now: Date = .now, calendar: Calendar = .current) -> Due {
        let due = dueDate(calendar)
        if now >= due { return .overdue }
        let days = calendar.dateComponents([.day], from: now, to: due).day ?? .max
        return days <= 30 ? .dueSoon : .ok
    }
}
