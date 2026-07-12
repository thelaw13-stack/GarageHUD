import Foundation

/// A single thing Fleet Steward has *noticed* — never a command, never a guess dressed
/// as fact. Per the Constitution: Steward observes, exposes evidence, states its
/// confidence, and only then advises. Every observation carries the data it was drawn
/// from and a confidence level so the interface can "show confidence, never pretend
/// certainty."
public struct StewardObservation: Identifiable, Hashable, Sendable {
    public enum Tone: Sendable, Equatable {
        case informational   // a neutral fact worth surfacing
        case caution         // a likely gap the owner should weigh
        case advisory        // a stronger, time- or safety-sensitive nudge
    }

    /// Where the underlying data came from — drives how much certainty we may claim.
    public enum Provenance: Sendable, Equatable {
        case recorded        // logged parts / notes / dyno — GarageHUD's own memory
        case derived         // computed from recorded data (arithmetic, dates)
        case estimatedLive   // real-time telemetry that is *estimated* (simulated, no hardware)
        case measuredLive    // real-time telemetry read from an actual OBD-II adapter
    }

    public let id = UUID()
    /// Evidence-first phrasing ("I observed… / The data suggests…"), never "I think…".
    public let statement: String
    /// The concrete data the statement rests on, shown to the owner.
    public let evidence: String
    /// 0–100. Deterministic facts sit high; heuristic gaps sit lower and say so.
    public let confidence: Int
    public let tone: Tone
    public let provenance: Provenance

    public init(statement: String, evidence: String, confidence: Int, tone: Tone, provenance: Provenance) {
        self.statement = statement
        self.evidence = evidence
        self.confidence = max(0, min(100, confidence))
        self.tone = tone
        self.provenance = provenance
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: StewardObservation, rhs: StewardObservation) -> Bool { lhs.id == rhs.id }
}
