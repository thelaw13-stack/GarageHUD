import Foundation

/// Fleet-level reasoning — the part of "Fleet Steward" that only makes sense across more
/// than one car. Per-vehicle rules live in `Steward.observe(_:)`; these compare vehicles to
/// each other: which build returns the most power per dollar, which car has gone quiet while
/// another stays active, and gaps the whole garage shares.
///
/// Same discipline as everywhere: evidence-first, honest confidence, provenance. Silent
/// with fewer than two vehicles — there's no fleet to reason about.
public extension Steward {

    static func observeFleet(_ vehicles: [Vehicle]) -> [StewardObservation] {
        guard vehicles.count >= 2 else { return [] }
        var out: [StewardObservation] = []

        // 1. Value leader — of the cars with a real cost-per-hp figure, which is most efficient.
        let withValue = vehicles.compactMap { v -> (Vehicle, Double)? in
            v.costPerHorsepowerGained.map { (v, $0) }
        }
        if withValue.count >= 2,
           let best = withValue.min(by: { $0.1 < $1.1 }),
           let worst = withValue.max(by: { $0.1 < $1.1 }),
           best.0.id != worst.0.id {
            out.append(StewardObservation(
                statement: "I observed \(best.0.displayName) returns the most power per dollar in the fleet.",
                evidence: "\(dollars(best.1))/whp on \(best.0.displayName) vs \(dollars(worst.1))/whp on \(worst.0.displayName).",
                confidence: 96, tone: .informational, provenance: .derived))
        }

        // 2. Neglected car — one build has gone quiet while another is clearly active.
        let dated = vehicles.compactMap { v -> (Vehicle, Date)? in v.lastActivityDate.map { (v, $0) } }
        if dated.count >= 2,
           let quietest = dated.min(by: { $0.1 < $1.1 }),
           let freshest = dated.max(by: { $0.1 < $1.1 }),
           quietest.0.id != freshest.0.id {
            let quietDays = Calendar.current.dateComponents([.day], from: quietest.1, to: .now).day ?? 0
            let freshDays = Calendar.current.dateComponents([.day], from: freshest.1, to: .now).day ?? 0
            // Only worth saying when the neglect is real and the contrast is stark.
            if quietDays >= 90 && quietDays - freshDays >= 60 {
                out.append(StewardObservation(
                    statement: "Based on your history, \(quietest.0.displayName) has fallen behind the rest of the fleet.",
                    evidence: "\(quietest.0.displayName) last saw activity \(quietDays) days ago; \(freshest.0.displayName) was touched \(freshDays) days ago.",
                    confidence: 85, tone: quietDays >= 240 ? .advisory : .caution, provenance: .derived))
            }
        }

        // 3. Shared gap — the same build-integrity gap shows up on more than one car.
        for (category, label) in [(PartCategory.brakes, "braking"), (.fueling, "fueling"), (.cooling, "cooling")] {
            let affected = vehicles.filter { v in
                let installed = Set(v.parts.filter { $0.status == .installed }.map(\.category))
                let powerUp = (v.horsepowerGainedOverStock ?? 0) >= 40
                switch category {
                case .brakes: return (installed.contains(.suspension) || powerUp) && !installed.contains(.brakes)
                case .fueling, .cooling: return installed.contains(.forcedInduction) && !installed.contains(category)
                default: return false
                }
            }
            if affected.count >= 2 {
                out.append(StewardObservation(
                    statement: "The data suggests \(label) is a gap across multiple cars.",
                    evidence: "\(affected.map(\.displayName).joined(separator: " and ")) each show the same \(label) gap.",
                    confidence: 74, tone: .caution, provenance: .recorded))
            }
        }

        return out.sorted { rankFleet($0) > rankFleet($1) }
    }

    private static func rankFleet(_ o: StewardObservation) -> Int {
        switch o.tone {
        case .advisory: return 200 + o.confidence
        case .caution: return 100 + o.confidence
        case .informational: return o.confidence
        }
    }

    private static func dollars(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }
}
