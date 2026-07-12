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

/// A boost target for a range of RPM — one row of a tune profile. When the owner supplies
/// these, the live reasoning judges boost against what *this tune* is supposed to make at the
/// current RPM, rather than a single generic threshold.
public struct BoostBand: Sendable, Equatable, Hashable, Codable {
    public var rpmLow: Int
    public var rpmHigh: Int
    public var expectedLowPsi: Double
    public var expectedHighPsi: Double

    public init(rpmLow: Int, rpmHigh: Int, expectedLowPsi: Double, expectedHighPsi: Double) {
        self.rpmLow = rpmLow
        self.rpmHigh = rpmHigh
        self.expectedLowPsi = expectedLowPsi
        self.expectedHighPsi = expectedHighPsi
    }

    public func contains(rpm: Double) -> Bool { Double(rpmLow) <= rpm && rpm <= Double(rpmHigh) }
}

/// A vehicle's live operating limits. Generic thresholds (18 psi, 235°F) are meaningless
/// across wildly different builds — boost is irrelevant on a naturally aspirated car and
/// low on a big turbo setup. This gives each vehicle its own envelope, defaulting from what
/// we know about it, so a live rule only fires where the number actually means something.
///
/// The optional tune profile (`maxSustainedBoostPsi`, `expectedBoostByRPM`) is **opt-in**:
/// when empty, only the single generic boost caution applies, so nothing is fabricated for a
/// car whose tune hasn't been characterized. Sustained-vs-instantaneous duration and load
/// remain future work; the rules gate boost on throttle to avoid off-throttle false alarms.
public struct OperatingEnvelope: Sendable, Equatable, Hashable, Codable {
    public var coolantCautionF: Double
    public var coolantCriticalF: Double
    /// nil means "boost is not a meaningful signal for this car" (e.g. naturally aspirated).
    public var boostCautionPsi: Double?
    /// A hard ceiling the owner never wants exceeded (over-boost alarm). Opt-in.
    public var maxSustainedBoostPsi: Double?
    /// RPM-banded boost targets for this tune. Opt-in; when present, they supersede the single
    /// generic boost caution.
    public var expectedBoostByRPM: [BoostBand]

    public init(coolantCautionF: Double = 215, coolantCriticalF: Double = 235,
                boostCautionPsi: Double? = nil, maxSustainedBoostPsi: Double? = nil,
                expectedBoostByRPM: [BoostBand] = []) {
        self.coolantCautionF = coolantCautionF
        self.coolantCriticalF = coolantCriticalF
        self.boostCautionPsi = boostCautionPsi
        self.maxSustainedBoostPsi = maxSustainedBoostPsi
        self.expectedBoostByRPM = expectedBoostByRPM
    }

    /// A sane default derived from the record: boost only matters if forced induction is
    /// confirmed present. Coolant limits are conservative street values; no tune profile is
    /// assumed (that must be entered by the owner).
    public static func `default`(for vehicle: Vehicle) -> OperatingEnvelope {
        let boosted = vehicle.knowledge(of: .forcedInduction) == .confirmedPresent
        return OperatingEnvelope(coolantCautionF: 215, coolantCriticalF: 235,
                                 boostCautionPsi: boosted ? 18 : nil)
    }
}
