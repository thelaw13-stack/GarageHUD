import Foundation

/// A single wide-open-throttle pull, captured automatically from a live telemetry session — not a
/// manual save, but the Steward noticing a genuine run and grading what it actually saw. The
/// headline claims (ceiling breach, target-band compliance) are only as trustworthy as the boost
/// data behind them, so the report carries its own evidence band rather than asserting a verdict.
/// This is the same honesty pivot as everywhere else in GarageHUD, applied to a captured run.
public struct PullReport: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var startedAt: Date
    public var endedAt: Date
    /// "Simulated" or "OBD-II Adapter" — the feed context the run was captured under.
    public var feedLabel: String

    public var rpmStart: Double
    public var rpmPeak: Double
    public var rpmEnd: Double

    public var boostPeakPsi: Double?
    public var boostBreachedCeiling: Bool
    /// The ceiling in effect at capture time, recorded alongside the peak so a later tune change
    /// can't retroactively make an old report's verdict look wrong or right for the wrong reason.
    public var boostCeilingPsi: Double?

    /// Fraction of RPM-banded samples that landed on/over/under the tune target. Nil when the car
    /// has no tune profile (`expectedBoostByRPM`) — Steward never invents a target that isn't there.
    public var onTargetFraction: Double?
    public var overTargetFraction: Double?
    public var underTargetFraction: Double?

    public var coolantStartF: Double?
    public var coolantPeakF: Double?
    public var coolantDeltaF: Double?

    public var sampleCount: Int
    /// Fraction of boost samples during the pull that were decoded from a real adapter (vs.
    /// simulated or absent) — the direct input to `confidence`. Nil when no boost signal was ever
    /// present (an NA car, or a car with no boost PID configured).
    public var measuredBoostFraction: Double?
    /// How much this report's boost-related claims can be trusted — the same vocabulary as every
    /// other Steward observation (Confirmed / Strong / Moderate / Weak / Insufficient), scoped to
    /// what was actually measured during this specific run.
    public var confidence: ConfidenceBand

    public var durationSeconds: Double { endedAt.timeIntervalSince(startedAt) }

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date, feedLabel: String,
                rpmStart: Double, rpmPeak: Double, rpmEnd: Double,
                boostPeakPsi: Double?, boostBreachedCeiling: Bool, boostCeilingPsi: Double?,
                onTargetFraction: Double?, overTargetFraction: Double?, underTargetFraction: Double?,
                coolantStartF: Double?, coolantPeakF: Double?, coolantDeltaF: Double?,
                sampleCount: Int, measuredBoostFraction: Double?, confidence: ConfidenceBand) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.feedLabel = feedLabel
        self.rpmStart = rpmStart
        self.rpmPeak = rpmPeak
        self.rpmEnd = rpmEnd
        self.boostPeakPsi = boostPeakPsi
        self.boostBreachedCeiling = boostBreachedCeiling
        self.boostCeilingPsi = boostCeilingPsi
        self.onTargetFraction = onTargetFraction
        self.overTargetFraction = overTargetFraction
        self.underTargetFraction = underTargetFraction
        self.coolantStartF = coolantStartF
        self.coolantPeakF = coolantPeakF
        self.coolantDeltaF = coolantDeltaF
        self.sampleCount = sampleCount
        self.measuredBoostFraction = measuredBoostFraction
        self.confidence = confidence
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? .now
        endedAt = try c.decodeIfPresent(Date.self, forKey: .endedAt) ?? .now
        feedLabel = try c.decodeIfPresent(String.self, forKey: .feedLabel) ?? ""
        rpmStart = try c.decodeIfPresent(Double.self, forKey: .rpmStart) ?? 0
        rpmPeak = try c.decodeIfPresent(Double.self, forKey: .rpmPeak) ?? 0
        rpmEnd = try c.decodeIfPresent(Double.self, forKey: .rpmEnd) ?? 0
        boostPeakPsi = try c.decodeIfPresent(Double.self, forKey: .boostPeakPsi)
        boostBreachedCeiling = try c.decodeIfPresent(Bool.self, forKey: .boostBreachedCeiling) ?? false
        boostCeilingPsi = try c.decodeIfPresent(Double.self, forKey: .boostCeilingPsi)
        onTargetFraction = try c.decodeIfPresent(Double.self, forKey: .onTargetFraction)
        overTargetFraction = try c.decodeIfPresent(Double.self, forKey: .overTargetFraction)
        underTargetFraction = try c.decodeIfPresent(Double.self, forKey: .underTargetFraction)
        coolantStartF = try c.decodeIfPresent(Double.self, forKey: .coolantStartF)
        coolantPeakF = try c.decodeIfPresent(Double.self, forKey: .coolantPeakF)
        coolantDeltaF = try c.decodeIfPresent(Double.self, forKey: .coolantDeltaF)
        sampleCount = try c.decodeIfPresent(Int.self, forKey: .sampleCount) ?? 0
        measuredBoostFraction = try c.decodeIfPresent(Double.self, forKey: .measuredBoostFraction)
        confidence = try c.decodeIfPresent(ConfidenceBand.self, forKey: .confidence) ?? .insufficient
    }

    /// A compact one-liner for the timeline/biography — the memory, not the analysis.
    public var headline: String {
        var parts = ["\(Int(rpmStart))→\(Int(rpmPeak)) rpm"]
        if let peak = boostPeakPsi { parts.append("\(String(format: "%.1f", peak)) psi peak") }
        if boostBreachedCeiling { parts.append("over ceiling") }
        return parts.joined(separator: ", ")
    }

    /// The evidence-led verdict, in the Steward's voice — states what was seen, then how much to
    /// trust it, never the other way around.
    public var verdictStatement: String {
        if boostBreachedCeiling { return "This pull went over your boost ceiling." }
        if let over = overTargetFraction, over >= 0.5 { return "This pull ran high over target for most of the band." }
        if let under = underTargetFraction, under >= 0.5 { return "This pull ran under target for most of the band." }
        if onTargetFraction != nil { return "This pull tracked target through the band." }
        return "This pull was captured, but no boost signal was available to grade."
    }

    public var verdictEvidence: String {
        var pieces = [headline]
        if let on = onTargetFraction {
            pieces.append("on target \(Int(on * 100))% (over \(Int((overTargetFraction ?? 0) * 100))%, under \(Int((underTargetFraction ?? 0) * 100))%)")
        }
        if let delta = coolantDeltaF, delta != 0 {
            pieces.append("coolant \(delta > 0 ? "+" : "")\(Int(delta))°F over the pull")
        }
        pieces.append("\(sampleCount) samples, \(confidence.label.lowercased())")
        return pieces.joined(separator: "; ") + "."
    }
}
