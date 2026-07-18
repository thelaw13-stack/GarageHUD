import Foundation

/// Fleet-level reasoning — the part of "Fleet Steward" that only makes sense across more than
/// one car. Evidence-first, honest bands, deterministic identities and order, and — critically
/// — it never promotes an *undocumented* per-car gap into a confident fleet-wide claim. Only
/// confirmed facts aggregate. Silent with fewer than two vehicles.
public extension Steward {

    static func observeFleet(_ vehicles: [Vehicle], context: StewardContext = .live) -> [StewardObservation] {
        guard vehicles.count >= 2 else { return [] }
        var out: [StewardObservation] = []

        // 1. Value leader — approximate by construction (wheel dyno vs factory crank).
        let withValue = vehicles.compactMap { v -> (Vehicle, Double)? in
            v.costPerHorsepowerGained.map { (v, $0) }
        }
        if withValue.count >= 2,
           let best = withValue.min(by: { $0.1 < $1.1 }),
           let worst = withValue.max(by: { $0.1 < $1.1 }),
           best.0.id != worst.0.id {
            out.append(StewardObservation(
                ruleID: StewardRuleID.fleetValueLeader, subjectID: nil,
                statement: "I observed \(best.0.displayName) returns the most power per dollar in the fleet.",
                evidence: "~\(dollars(best.1))/whp on \(best.0.displayName) vs ~\(dollars(worst.1))/whp on \(worst.0.displayName). Approximate — wheel figures against factory crank ratings.",
                confidence: .moderate, tone: .informational, provenance: .derived))
        }

        // 2. Neglected car — a build gone quiet while another stays active. A car that's
        //    intentionally out of service is not a neglect candidate.
        let dated = vehicles
            .filter { !$0.serviceStatus.isInService }
            .compactMap { v -> (Vehicle, Date)? in v.lastActivityDate.map { (v, $0) } }
        if dated.count >= 2,
           let quietest = dated.min(by: { $0.1 < $1.1 }),
           let freshest = dated.max(by: { $0.1 < $1.1 }),
           quietest.0.id != freshest.0.id {
            let quietDays = context.days(from: quietest.1, to: context.now)
            let freshDays = context.days(from: freshest.1, to: context.now)
            if quietDays >= 90 && quietDays - freshDays >= 60 {
                out.append(StewardObservation(
                    ruleID: StewardRuleID.fleetNeglect, subjectID: quietest.0.id,
                    statement: "Based on your history, \(quietest.0.displayName) has fallen behind the rest of the fleet.",
                    evidence: "\(quietest.0.displayName) last saw activity \(quietDays) days ago; \(freshest.0.displayName) was touched \(freshDays) days ago.",
                    confidence: .strong, tone: quietDays >= 240 ? .advisory : .caution, provenance: .derived))
            }
        }

        // 3. Shared gap — only when *confirmed absent* on 2+ cars. Undocumented records never
        //    aggregate into a fleet-level warning (the review's key correction).
        for (category, label) in [(PartCategory.brakes, "braking"), (.fueling, "fueling"), (.cooling, "cooling")] {
            let affected = vehicles.filter { v in
                guard v.knowledge(of: category) == .confirmedAbsent else { return false }
                switch category {
                case .brakes:
                    return v.knowledge(of: .suspension) == .confirmedPresent || v.powerDemandsDrivelineAttention
                case .fueling, .cooling:
                    return v.knowledge(of: .forcedInduction) == .confirmedPresent
                default: return false
                }
            }
            if affected.count >= 2 {
                out.append(StewardObservation(
                    ruleID: StewardRuleID.fleetSharedGap(category), subjectID: nil,
                    statement: "The data suggests \(label) is a confirmed gap across multiple cars.",
                    evidence: "\(affected.map(\.displayName).joined(separator: " and ")) each have the factory \(label) confirmed while running more load.",
                    confidence: .strong, tone: .caution, provenance: .recorded))
            }
        }

        return out.sorted(by: ordered)
    }
}
