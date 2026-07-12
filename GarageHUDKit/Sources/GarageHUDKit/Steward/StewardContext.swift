import Foundation

/// The clock and calendar the reasoning runs against, injected rather than reached for. This
/// makes every rule a pure function of (model, context): tests pin a fixed `now`, historical
/// replay is possible, and day-count math no longer drifts with wall-clock time, DST, or
/// timezone. Production passes `.live`.
public struct StewardContext: Sendable {
    public var now: Date
    public var calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public static var live: StewardContext { StewardContext() }

    /// Whole days between two instants, in this context's calendar.
    public func days(from start: Date, to end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}

/// A vehicle's live operating limits. Generic thresholds (18 psi, 235°F) are meaningless
/// across wildly different builds — boost is irrelevant on a naturally aspirated car and
/// low on a big turbo setup. This gives each vehicle its own envelope, defaulting from what
/// we know about it, so a live rule only fires where the number actually means something.
///
/// NOTE: this is a first envelope — coolant caution/critical and a single boost caution.
/// RPM-banded boost targets, sustained-vs-instantaneous duration, and load are future work;
/// the rules already gate boost on throttle to avoid off-throttle false alarms.
public struct OperatingEnvelope: Sendable, Equatable, Hashable, Codable {
    public var coolantCautionF: Double
    public var coolantCriticalF: Double
    /// nil means "boost is not a meaningful signal for this car" (e.g. naturally aspirated).
    public var boostCautionPsi: Double?

    public init(coolantCautionF: Double = 215, coolantCriticalF: Double = 235, boostCautionPsi: Double? = nil) {
        self.coolantCautionF = coolantCautionF
        self.coolantCriticalF = coolantCriticalF
        self.boostCautionPsi = boostCautionPsi
    }

    /// A sane default derived from the record: boost only matters if forced induction is
    /// confirmed present. Coolant limits are conservative street values until the owner
    /// tailors them.
    public static func `default`(for vehicle: Vehicle) -> OperatingEnvelope {
        let boosted = vehicle.knowledge(of: .forcedInduction) == .confirmedPresent
        return OperatingEnvelope(coolantCautionF: 215, coolantCriticalF: 235,
                                 boostCautionPsi: boosted ? 18 : nil)
    }
}
