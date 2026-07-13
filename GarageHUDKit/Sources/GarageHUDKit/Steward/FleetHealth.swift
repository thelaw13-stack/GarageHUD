import Foundation

/// Fleet-level maintenance rollup — how many cars need service right now — kept pure so the
/// Garage header badge is testable without any UI. Out-of-service cars are skipped: you're not
/// driving them, so their intervals aren't ticking (consistent with the reminder engine).
public enum FleetHealth {
    public struct ServiceDue: Equatable, Sendable {
        public var overdue: Int
        public var dueSoon: Int
        public var total: Int { overdue + dueSoon }
    }

    public static func serviceDue(for vehicles: [Vehicle], now: Date = .now,
                                  calendar: Calendar = .current) -> ServiceDue {
        var overdue = 0, dueSoon = 0
        for vehicle in vehicles where !vehicle.serviceStatus.isInService {
            switch vehicle.maintenanceDue(now: now, calendar: calendar) {
            case .overdue: overdue += 1
            case .dueSoon: dueSoon += 1
            case .ok: break
            }
        }
        return ServiceDue(overdue: overdue, dueSoon: dueSoon)
    }

    /// The single most-pressing car to service: any overdue car first (soonest due date wins), then
    /// the most-pressing due-soon car. Out-of-service cars are skipped. Nil if nothing needs service.
    public static func mostUrgent(in vehicles: [Vehicle], now: Date = .now,
                                  calendar: Calendar = .current) -> Vehicle? {
        // Rank: overdue (2) before dueSoon (1); within a rank, the earliest due date is most urgent.
        func rank(_ v: Vehicle) -> Int {
            switch v.maintenanceDue(now: now, calendar: calendar) {
            case .overdue: return 2; case .dueSoon: return 1; case .ok: return 0
            }
        }
        func soonestDue(_ v: Vehicle) -> Date {
            v.maintenance.map { $0.dueDate(calendar) }.min() ?? .distantFuture
        }
        return vehicles
            .filter { !$0.serviceStatus.isInService && rank($0) > 0 }
            .max { a, b in rank(a) != rank(b) ? rank(a) < rank(b) : soonestDue(a) > soonestDue(b) }
    }
}
