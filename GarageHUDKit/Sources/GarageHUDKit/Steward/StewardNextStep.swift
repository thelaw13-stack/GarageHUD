import Foundation

/// The single most logical thing to do next — the Constitution's "advises" pillar, kept honest.
/// It doesn't invent goals; it prioritizes what the recorded data already says: an active
/// rebuild first, then a safety/time-sensitive advisory, then a real support gap for the power,
/// then a stale tune. Confidence is inherited from whichever fact drives it.
public struct NextStep: Equatable, Sendable {
    public let action: String
    public let rationale: String
    public let confidence: ConfidenceBand
    /// The observation this step was drawn from, when there is one — so the UI can offer that
    /// observation's resolution options in place. A step that names an action must be actionable;
    /// nil only when the fix lives elsewhere on the same screen (e.g. the rebuild checklist).
    public let source: StewardObservation?

    public init(action: String, rationale: String, confidence: ConfidenceBand,
                source: StewardObservation? = nil) {
        self.action = action
        self.rationale = rationale
        self.confidence = confidence
        self.source = source
    }
}

public extension Steward {

    static func nextStep(_ vehicle: Vehicle, context: StewardContext = .live) -> NextStep? {
        // 1. A car that's apart: the immediate priority is getting it back together.
        if vehicle.serviceStatus.isInService {
            let flagged = vehicle.partsFlaggedForRebuild.count
            let flaggedNote = flagged > 0 ? " · \(flagged) part\(flagged == 1 ? "" : "s") to inspect/replace" : ""
            if let progress = vehicle.serviceStatus.progressText,
               vehicle.serviceStatus.completedCount < vehicle.serviceStatus.checklist.count {
                return NextStep(action: "Finish the \(reasonPhrase(vehicle.serviceStatus.reason))",
                                rationale: "\(progress)\(flaggedNote).", confidence: .confirmed)
            }
            return NextStep(action: "Add rebuild tasks, or mark it back in service",
                            rationale: "It's out of service with nothing left to track\(flaggedNote).",
                            confidence: .strong)
        }

        let observations = observe(vehicle, context: context)

        // 2. A safety- or time-sensitive advisory outranks build coherence.
        if let advisory = observations.first(where: { $0.tone == .advisory }) {
            return NextStep(action: advisoryAction(advisory),
                            rationale: advisory.evidence, confidence: advisory.confidence,
                            source: advisory)
        }

        // 3. The build's own open item — shore up support for the power it makes. If a part is
        //    already planned for it, the step is to install it, not to go find one. The matching
        //    gap observation (when the Steward emitted one) rides along so the step resolves in
        //    place (confirm stock / add the part).
        if let a = assess(vehicle),
           let open = a.subsystems.first(where: { $0.status != .supported }) {
            let gapObservation = PartCategory(rawValue: open.id).flatMap { category in
                observations.first { $0.ruleID == StewardRuleID.gap(category) }
            }
            if open.planned {
                return NextStep(action: "Install the planned \(open.label.lowercased()) upgrade",
                                rationale: "\(a.powerSummary); \(open.label.lowercased()) is on your wishlist but not yet installed.",
                                confidence: .strong, source: gapObservation)
            }
            let verb = open.status == .openItem ? "Address" : "Document"
            return NextStep(action: "\(verb) \(open.label.lowercased()) for this power level",
                            rationale: "\(a.powerSummary); \(open.label.lowercased()) "
                                + (open.status == .openItem ? "is the open item." : "isn't documented."),
                            confidence: a.confidence, source: gapObservation)
        }

        // 4. A tune that no longer matches the hardware.
        if let stale = observations.first(where: { $0.ruleID == StewardRuleID.tuneStale }) {
            return NextStep(action: "Re-dyno the current setup",
                            rationale: stale.evidence, confidence: stale.confidence,
                            source: stale)
        }

        // 5. Any remaining caution.
        if let caution = observations.first(where: { $0.tone == .caution }) {
            return NextStep(action: cautionAction(caution),
                            rationale: caution.evidence, confidence: caution.confidence,
                            source: caution)
        }

        return nil
    }

    private static func reasonPhrase(_ reason: String) -> String {
        let r = reason.lowercased()
        if r.contains("teardown") { return "engine teardown" }
        if r.contains("rebuild") { return "rebuild" }
        return reason.isEmpty ? "service work" : reason.split(separator: "—").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? "service work"
    }

    private static func advisoryAction(_ o: StewardObservation) -> String {
        if StewardRuleID.isMaintenance(o.ruleID) {
            return "Take care of the overdue \(o.statement.replacingOccurrences(of: " is overdue.", with: "").lowercased())"
        }
        switch o.ruleID {
        case StewardRuleID.buildQuiet: return "Log some activity — a note, a drive, or a fresh pull"
        case StewardRuleID.liveCoolantCritical: return "Back off — coolant is at its limit"
        default: return "Look into \(o.statement.lowercased())"
        }
    }

    private static func cautionAction(_ o: StewardObservation) -> String {
        if let cat = StewardRuleID.gapCategory(from: o.ruleID) {
            return "Document or upgrade the \(cat.rawValue.lowercased())"
        }
        switch o.ruleID {
        case StewardRuleID.dynoPlateau: return "Investigate the dyno plateau"
        case StewardRuleID.sequenceFIAheadOfFueling: return "Confirm the fueling is caught up to the boost"
        default: return "Address: \(o.statement.lowercased())"
        }
    }
}
