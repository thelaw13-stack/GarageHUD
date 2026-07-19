import Foundation

/// A proposed dyno wheel-horsepower entry that is physically implausible — almost certainly a
/// slipped digit. Wheel horsepower is a reasoning spine the same way the odometer is: it decides
/// `hasMeasuredPower`, the "N whp measured" headline, gain-over-stock, cost-per-hp, and the LLM
/// grounding line "Measured N whp [Strong evidence]". So one fat-fingered dyno states an absurd
/// number as *measured fact* everywhere at once — the very thing this app exists not to do. These
/// checks warn at entry time; they never block, because the record belongs to the owner and a
/// genuine (if wild) figure must always be loggable — the same contract as `OdometerAnomaly`.
public enum DynoAnomaly: Equatable, Sendable {
    /// The proposed wheel horsepower is beyond what a street or strip car makes — a likely typo.
    case implausiblyHigh(whp: Int)
    /// The proposed figure is zero or negative, so it will not count as a measurement at all.
    case notPositive

    /// The calm, non-blocking caution to show next to the entry field.
    public var caution: String {
        switch self {
        case .implausiblyHigh(let whp):
            return "\(whp.formatted(.number.grouping(.automatic))) whp is beyond what a street or strip car makes — double-check for a slipped digit, or save if it's real."
        case .notPositive:
            return "A dyno needs a positive wheel-horsepower figure to count as a measurement — this will log as a session with no number."
        }
    }
}

public extension Vehicle {
    /// Above this wheel horsepower a logged dyno figure is flagged as a likely typo. Generous on
    /// purpose: a 1,500 whp build is real; a single entry of 2,000+ almost always means a slipped
    /// digit (a decimal-pad "4770" that should have been "477"). Mirrors `implausibleMilesPerDay`.
    static let implausibleWheelHorsepower = 2_000

    /// Judge a proposed dyno wheel-hp figure BEFORE it is saved. Returns nil when the figure is
    /// unremarkable (including nil — nothing entered yet is not an anomaly). Absolute, not relative
    /// to history: an implausible number is implausible on the first dyno as much as the tenth.
    static func dynoAnomaly(proposingWheelHorsepower whp: Double?) -> DynoAnomaly? {
        guard let whp else { return nil }
        if whp <= 0 { return .notPositive }
        if whp > Double(implausibleWheelHorsepower) { return .implausiblyHigh(whp: Int(whp)) }
        return nil
    }
}
