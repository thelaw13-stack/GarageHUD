import Foundation

/// Owner-calibrated reasoning windows — the opposite of the guesses in `docs/STEWARD_THRESHOLDS.md`.
/// Each value here is a number Tim set for how *he* builds and uses his cars, recorded with its
/// rationale so it stops hiding among the invented ones. New owner-calibrated constants land here;
/// the eventual goal (Fable's structural note) is to pull every judgment threshold into a home like
/// this so a guess can't be added without declaring itself.
public enum StewardThresholds {

    /// Owner-calibrated (Tim, 2026-07-18): how long fueling support can lag behind forced induction
    /// before it reads as actually running boost under-fueled. A build's parts commonly install a
    /// few weeks apart, so only a month-plus gap is a real "ran it lean" signal — 14 was flagging
    /// normal build cadence. (The date gap is still a proxy; the truer signal is whether the car was
    /// *driven* between the two — noted as a follow-up, not this number.)
    public static let sequenceLagFlagDays = 30

    /// Owner-calibrated (Tim, 2026-07-18): a record reads as "quiet" after a quarter with nothing
    /// new logged. Informational only, and never for a car deliberately in service. (Was 180 — too
    /// eager for a fleet that mixes daily drivers with occasional project cars.)
    public static let quietRecordDays = 90

    // Note: the driveline-attention wheel-HP level (450) is the other owner-calibrated value; it
    // lives on `Vehicle.drivelineAttentionWheelHP` where the power reasoning uses it (W-044).
}
