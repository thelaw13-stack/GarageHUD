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
}
