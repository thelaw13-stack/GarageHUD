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

    public struct ServiceFocus: Equatable, Sendable {
        public var vehicleID: UUID
        public var vehicleName: String
        public var itemID: UUID
        public var itemName: String
        public var due: MaintenanceItem.Due
        public var urgencyAnchor: Date
        public var milesRemaining: Int?
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
        guard let focus = mostUrgentService(in: vehicles, now: now, calendar: calendar) else { return nil }
        return vehicles.first { $0.id == focus.vehicleID }
    }

    /// The single most-pressing maintenance item across the fleet. This powers the Garage header's
    /// service jump while keeping the reasoning pure and testable.
    public static func mostUrgentService(in vehicles: [Vehicle], now: Date = .now,
                                         calendar: Calendar = .current) -> ServiceFocus? {
        struct Candidate {
            var focus: ServiceFocus
            var rank: Int
        }

        func rank(_ due: MaintenanceItem.Due) -> Int {
            switch due {
            case .overdue: return 2
            case .dueSoon: return 1
            case .ok: return 0
            }
        }

        func urgencyAnchor(for item: MaintenanceItem, due: MaintenanceItem.Due) -> Date {
            let dueDate = item.dueDate(calendar)
            let timeDue = item.due(now: now, calendar: calendar)
            switch due {
            case .overdue:
                return timeDue == .overdue ? dueDate : now
            case .dueSoon:
                if timeDue == .dueSoon { return dueDate }
                return calendar.date(byAdding: .day, value: 30, to: now) ?? now
            case .ok:
                return .distantFuture
            }
        }

        let candidates: [Candidate] = vehicles.flatMap { vehicle -> [Candidate] in
            guard !vehicle.serviceStatus.isInService else { return [] }
            let mileage = vehicle.currentMileage
            return vehicle.maintenance.compactMap { item in
                let due = item.due(now: now, calendar: calendar, currentMileage: mileage)
                guard due != .ok else { return nil }
                return Candidate(
                    focus: ServiceFocus(
                        vehicleID: vehicle.id,
                        vehicleName: vehicle.displayName,
                        itemID: item.id,
                        itemName: item.name,
                        due: due,
                        urgencyAnchor: urgencyAnchor(for: item, due: due),
                        milesRemaining: item.milesUntilDue(currentMileage: mileage)
                    ),
                    rank: rank(due)
                )
            }
        }

        return candidates.sorted { a, b in
            if a.rank != b.rank { return a.rank > b.rank }
            if a.focus.urgencyAnchor != b.focus.urgencyAnchor {
                return a.focus.urgencyAnchor < b.focus.urgencyAnchor
            }
            let aMiles = a.focus.milesRemaining ?? .max
            let bMiles = b.focus.milesRemaining ?? .max
            if aMiles != bMiles { return aMiles < bMiles }
            if a.focus.vehicleName != b.focus.vehicleName {
                return a.focus.vehicleName.localizedStandardCompare(b.focus.vehicleName) == .orderedAscending
            }
            return a.focus.itemName.localizedStandardCompare(b.focus.itemName) == .orderedAscending
        }.first?.focus
    }
}
