import Foundation

/// A proposed odometer entry that disagrees with the record. The odometer is the reasoning
/// spine — `currentMileage`, the learned driving rate, and every mileage-based due state derive
/// from event readings — so one fat-fingered entry silently poisons all of them. These checks
/// warn at entry time; they never block, because the record belongs to the owner and a genuine
/// correction (a replaced cluster, a typo being fixed) must always be loggable.
public enum OdometerAnomaly: Equatable, Sendable {
    /// The proposed reading is lower than a reading already on record at or before this date.
    case regression(priorReading: Int, priorDate: Date)
    /// The implied driving rate since the last dated reading is implausibly high (a likely typo).
    case implausibleRate(milesPerDay: Int)

    /// The calm, non-blocking caution to show next to the entry field.
    public var caution: String {
        switch self {
        case .regression(let prior, let date):
            let d = date.formatted(date: .abbreviated, time: .omitted)
            return "Lower than the \(prior.formatted(.number.grouping(.automatic))) mi already logged on \(d) — double-check, or save if this is a correction."
        case .implausibleRate(let rate):
            return "That's ~\(rate.formatted(.number.grouping(.automatic))) mi/day since the last reading — double-check for a typo."
        }
    }
}

public extension Vehicle {
    /// Above this implied daily rate a new reading is flagged as a likely typo. Generous on
    /// purpose: an 800-mi road-trip day is real; 1,000+ sustained from a single entry usually
    /// means a slipped digit.
    static let implausibleMilesPerDay = 1_000

    /// Judge a proposed odometer entry against the existing record, BEFORE it is saved.
    /// Returns nil when the entry is unremarkable. When editing an existing event, call this on
    /// a copy of the vehicle with that event removed so it isn't compared against itself.
    func odometerAnomaly(proposing reading: Int, on date: Date) -> OdometerAnomaly? {
        let readings = buildEvents.compactMap { e in e.mileage.map { (date: e.date, miles: $0) } }

        if let prior = readings.filter({ $0.date <= date }).max(by: { $0.miles < $1.miles }),
           prior.miles > reading {
            return .regression(priorReading: prior.miles, priorDate: prior.date)
        }

        if let last = readings.filter({ $0.date < date }).max(by: { $0.date < $1.date }),
           reading > last.miles {
            let days = max(date.timeIntervalSince(last.date) / 86_400, 1.0 / 24)
            let rate = Double(reading - last.miles) / days
            if rate > Double(Self.implausibleMilesPerDay) {
                return .implausibleRate(milesPerDay: Int(rate))
            }
        }
        return nil
    }
}
