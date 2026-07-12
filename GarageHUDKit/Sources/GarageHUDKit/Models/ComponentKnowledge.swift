import Foundation

/// What we actually *know* about a subsystem — the distinction the review demands between
/// "not logged" and "not installed". Absence of a logged part is not evidence of a missing
/// physical system; it's just an undocumented one.
public enum ComponentKnowledge: Sendable, Equatable {
    case confirmedPresent   // an installed part in this category is on record
    case confirmedAbsent    // the owner confirmed the factory system remains (no upgrade)
    case undocumented       // nothing logged either way, but the record has other content
    case unknown            // the record is effectively empty — we know nothing at all
}

/// The measurement basis behind a horsepower figure. Comparing a measured wheel number
/// against a factory *crank* rating is an approximation, and the reasoning must say so
/// rather than presenting a dollars-per-hp figure as if it were dyno-corrected truth.
public enum PowerBasis: String, Sendable, Codable, Equatable, Hashable {
    case factoryCrank       // manufacturer rating, at the crank
    case estimatedCrank     // an estimate referred to the crank
    case measuredWheel      // measured on a chassis dyno, at the wheels
    case unknown

    public var describes: String {
        switch self {
        case .factoryCrank: return "factory crank"
        case .estimatedCrank: return "estimated crank"
        case .measuredWheel: return "measured wheel"
        case .unknown: return "unspecified"
        }
    }
}

public extension Vehicle {
    /// What we know about a given subsystem, honestly. An empty record yields `.unknown`
    /// (so a freshly created or barely-imported vehicle is never warned at), a logged install
    /// yields `.confirmedPresent`, an explicit stock confirmation yields `.confirmedAbsent`,
    /// and everything else is `.undocumented` — a gap in the *record*, not proof of a gap in
    /// the *car*.
    func knowledge(of category: PartCategory) -> ComponentKnowledge {
        if parts.isEmpty && confirmedStockSystems.isEmpty { return .unknown }
        if parts.contains(where: { $0.category == category && $0.status == .installed }) {
            return .confirmedPresent
        }
        if confirmedStockSystems.contains(category) { return .confirmedAbsent }
        return .undocumented
    }

    /// A rough completeness signal used to grade `.undocumented` gaps: a richly documented
    /// build with a missing category is more suspicious than a sparse imported record.
    var isWellDocumented: Bool { installedPartsCount >= 6 }

    /// The live operating limits for this car — the owner's override, or a default derived
    /// from what we know about it.
    var operatingEnvelope: OperatingEnvelope { operatingEnvelopeOverride ?? .default(for: self) }
}
