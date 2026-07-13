import Foundation

/// A synthesized read on whether a modified build is *coherent* — do the load-bearing systems
/// scale with the power adder? This is the judgment a builder makes at a glance: strong forced
/// induction is only as good as the fueling, cooling, internals, clutch, and brakes behind it.
///
/// Unlike the per-gap observations (which say "act on this"), the assessment shows the whole
/// support picture at once — what's covered *and* what isn't — calmly and honestly. Every
/// status derives from `ComponentKnowledge`, so an *undocumented* system is shown as unknown,
/// never asserted missing.
public struct BuildAssessment: Equatable, Sendable {
    public enum Status: Sendable, Equatable {
        case supported      // a matching upgrade is on record
        case openItem       // confirmed stock while under load — a real gap
        case undocumented   // nothing logged either way at this power level
    }

    public struct Subsystem: Identifiable, Equatable, Sendable {
        public let id: String            // the category rawValue — stable
        public let label: String
        public let role: String          // why it's load-bearing, e.g. "hold cylinder pressure"
        public let status: Status
    }

    /// e.g. "477 whp · +276 over an estimated stock wheel baseline".
    public let powerSummary: String
    public let subsystems: [Subsystem]
    /// A calm one-line verdict synthesized from the subsystem picture.
    public let headline: String
    /// How strongly the picture is evidenced — STRONG when every system is confirmed either
    /// way, MODERATE when parts of it rest on undocumented absence.
    public let confidence: ConfidenceBand
}

public extension Steward {

    /// Assess a *modified* build's coherence. Returns nil for an unmodified or effectively empty
    /// record (nothing to assess), or a car whose knowledge is `.unknown` throughout.
    static func assess(_ vehicle: Vehicle) -> BuildAssessment? {
        let forcedInduction = vehicle.knowledge(of: .forcedInduction) == .confirmedPresent
        let gain = vehicle.horsepowerGainedOverStock ?? 0
        let powerUp = gain >= 40
        guard forcedInduction || powerUp else { return nil }

        let suspensionUp = vehicle.knowledge(of: .suspension) == .confirmedPresent

        // The load-bearing systems and when each becomes relevant to *this* build.
        struct Def { let cat: PartCategory; let label: String; let role: String; let relevant: Bool }
        let defs: [Def] = [
            Def(cat: .fueling,   label: "Fueling",          role: "feed the extra air",          relevant: forcedInduction),
            Def(cat: .cooling,   label: "Cooling",          role: "manage the added heat",       relevant: forcedInduction),
            Def(cat: .engine,    label: "Engine internals", role: "hold cylinder pressure",      relevant: forcedInduction && gain >= 80),
            Def(cat: .drivetrain,label: "Clutch / drivetrain", role: "put the power down",       relevant: powerUp),
            Def(cat: .brakes,    label: "Braking",          role: "match stopping to the power", relevant: powerUp || suspensionUp),
        ]

        let subsystems: [BuildAssessment.Subsystem] = defs.filter(\.relevant).map { def in
            let status: BuildAssessment.Status
            switch vehicle.knowledge(of: def.cat) {
            case .confirmedPresent: status = .supported
            case .confirmedAbsent:  status = .openItem
            case .undocumented, .unknown: status = .undocumented
            }
            return BuildAssessment.Subsystem(id: def.cat.rawValue, label: def.label, role: def.role, status: status)
        }
        guard !subsystems.isEmpty else { return nil }

        let openItems = subsystems.filter { $0.status == .openItem }
        let undocumented = subsystems.filter { $0.status == .undocumented }
        let unresolved = openItems + undocumented
        let supportedCount = subsystems.count - unresolved.count

        let headline: String
        if unresolved.isEmpty {
            headline = "A well-supported build — every load-bearing system scales with the power."
        } else if unresolved.count == 1 {
            let name = unresolved[0].label.lowercased()
            let verb = unresolved[0].status == .openItem ? "is the open item" : "isn't documented"
            headline = "Strong build; \(name) \(verb) at this power level."
        } else {
            let names = unresolved.map { $0.label.lowercased() }.joined(separator: ", ")
            headline = "\(supportedCount) of \(subsystems.count) supporting systems are covered; \(names) still need attention."
        }

        // Confirmed either way → strong. Any inference from undocumented absence → moderate.
        let confidence: ConfidenceBand = undocumented.isEmpty ? .strong : .moderate

        let powerSummary: String = {
            guard let hp = vehicle.currentHorsepowerEstimate else { return "Power not yet measured" }
            let base = "\(Int(hp)) whp"
            return gain > 0 ? base + " · +\(Int(gain)) over an estimated stock wheel baseline" : base
        }()

        return BuildAssessment(powerSummary: powerSummary, subsystems: subsystems,
                               headline: headline, confidence: confidence)
    }
}
