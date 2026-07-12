import Foundation

/// How much the evidence itself supports a claim — a grade, not a fabricated probability.
/// Per the review: hand-authored percentages like "88%" imply a statistical rigor the system
/// doesn't have. A band says only what we can honestly stand behind, and is derived from how
/// complete the underlying evidence is.
public enum ConfidenceBand: Int, Sendable, Equatable, CaseIterable, Comparable {
    case insufficient = 0   // not enough recorded to say anything
    case weak = 1           // a hint; could easily be an incomplete record
    case moderate = 2       // reasonable inference, not confirmed
    case strong = 3         // confirmed inputs, well-supported conclusion
    case confirmed = 4      // a directly recorded or arithmetic fact

    public static func < (l: ConfidenceBand, r: ConfidenceBand) -> Bool { l.rawValue < r.rawValue }

    /// Trust-calibrated label shown to the owner — descriptive, never a fabricated percentage.
    public var label: String {
        switch self {
        case .insufficient: return "Insufficient Data"
        case .weak: return "Needs Verification"
        case .moderate: return "Moderate Evidence"
        case .strong: return "Strong Evidence"
        case .confirmed: return "Confirmed"
        }
    }

    /// Spoken form, e.g. "strong evidence".
    public var spokenPhrase: String {
        switch self {
        case .insufficient: return "insufficient data"
        case .weak: return "weak evidence"
        case .moderate: return "moderate evidence"
        case .strong: return "strong evidence"
        case .confirmed: return "confirmed"
        }
    }
}

/// A single thing Fleet Steward has *noticed* — never a command, never a guess dressed as
/// fact. Per the Constitution: Steward observes, exposes evidence, states how strong that
/// evidence is, and only then advises. Every observation carries the data it was drawn from
/// and an evidence band so the interface can "show confidence, never pretend certainty."
public struct StewardObservation: Identifiable, Hashable, Sendable {
    public enum Tone: Sendable, Equatable {
        case informational   // a neutral fact worth surfacing
        case caution         // a likely gap the owner should weigh
        case advisory        // a stronger, time- or safety-sensitive nudge
    }

    /// Where the underlying data came from — bounds how much certainty we may claim.
    public enum Provenance: Sendable, Equatable {
        case recorded        // logged parts / notes / dyno — GarageHUD's own memory
        case derived         // computed from recorded data (arithmetic, dates)
        case estimatedLive   // real-time telemetry that is *estimated* (simulated)
        case measuredLive    // real-time telemetry read from an actual OBD-II adapter
    }

    /// A stable rule identifier (e.g. "gap.fueling", "fleet.sharedGap.cooling"). Combined with
    /// the subject it gives a *deterministic* identity, so recomputing a briefing doesn't mint
    /// fresh identities and churn the SwiftUI diff.
    public let ruleID: String
    /// The vehicle this observation is about, or nil for fleet-level observations.
    public let subjectID: UUID?
    /// Evidence-first phrasing ("I observed… / The data suggests…"), never "I think…".
    public let statement: String
    /// The concrete data the statement rests on, shown to the owner.
    public let evidence: String
    /// How strong the evidence is — a grade, not a fake percentage.
    public let confidence: ConfidenceBand
    public let tone: Tone
    public let provenance: Provenance

    /// Deterministic: same rule + same subject → same id across rebuilds.
    public var id: String { subjectID.map { "\(ruleID)#\($0.uuidString)" } ?? ruleID }

    public init(ruleID: String, subjectID: UUID? = nil, statement: String, evidence: String,
                confidence: ConfidenceBand, tone: Tone, provenance: Provenance) {
        self.ruleID = ruleID
        self.subjectID = subjectID
        self.statement = statement
        self.evidence = evidence
        self.confidence = confidence
        self.tone = tone
        self.provenance = provenance
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: StewardObservation, rhs: StewardObservation) -> Bool { lhs.id == rhs.id }
}
