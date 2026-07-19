import Foundation

/// A concrete fix the owner can take for a Steward observation — the "solution with options" behind
/// a colored action note. Pure and testable: mapping an observation to its options lives here; the
/// dashboard just presents them and performs the chosen one.
public enum ResolutionAction: Equatable, Sendable {
    case markServiced(UUID)          // a maintenance item is due → log it done
    case editSchedule(UUID)          // adjust that item's interval
    case markBackInService           // car is out of service → return it
    case confirmStock(PartCategory)  // an undocumented system is actually factory-stock
    case addPart(PartCategory)       // …or add the part that fills the gap
    case logPerformance              // stale/plateaued power → record a dyno run
    case logActivity                 // quiet build history → log recent work
    case reviewParts                 // undated/out-of-sequence parts → open the parts list
    case editEnvelope                // live-telemetry limit → tune the operating envelope
    case acknowledgePull(UUID)       // flagged pull inspected/resolved → date it, log it, clear it
}

public struct ResolutionOption: Identifiable, Equatable, Sendable {
    public let title: String
    public let action: ResolutionAction
    public var id: String { title }
    public init(_ title: String, _ action: ResolutionAction) { self.title = title; self.action = action }
}

public enum StewardResolution {
    /// The options offered for an observation, most-recommended first. Empty when there's no
    /// concrete in-app fix (the note is informational only), in which case the row isn't tappable.
    public static func options(for obs: StewardObservation, in vehicle: Vehicle) -> [ResolutionOption] {
        let id = obs.ruleID

        if StewardRuleID.isMaintenance(id), let item = StewardRuleID.maintenanceItemID(from: id) {
            return [.init("Mark serviced", .markServiced(item)),
                    .init("Adjust interval…", .editSchedule(item))]
        }
        if id == StewardRuleID.serviceInService {
            return [.init("Mark back in service", .markBackInService)]
        }
        if let cat = StewardRuleID.gapCategory(from: id) {
            // The verbs must reflect what's already known. Once the owner has confirmed the
            // system factory-stock, offering "confirm it's stock" again is a circular ask —
            // tapping it is a no-op and the surface never resolves (Tim's Fozzy report). The
            // remaining honest door for a confirmed-stock system under load is the upgrade.
            if vehicle.knowledge(of: cat) == .confirmedAbsent {
                return [.init("Add the \(cat.rawValue.lowercased()) upgrade", .addPart(cat))]
            }
            return [.init("Confirm \(cat.rawValue.lowercased()) is factory-stock", .confirmStock(cat)),
                    .init("Add the \(cat.rawValue.lowercased()) part", .addPart(cat))]
        }
        switch id {
        case StewardRuleID.tuneStale, StewardRuleID.dynoPlateau:
            return [.init("Log a dyno result", .logPerformance)]
        case StewardRuleID.buildQuiet, StewardRuleID.fleetNeglect:
            return [.init("Log recent work", .logActivity)]
        case StewardRuleID.dataUndatedParts, StewardRuleID.sequenceFIAheadOfFueling:
            return [.init("Review parts", .reviewParts)]
        case StewardRuleID.dataOdometerRegression:
            return [.init("Review the timeline", .logActivity)]
        default:
            // A flagged pull's first door must actually clear it (W-053): acknowledge is the
            // mechanically honest resolution; adjusting the envelope tunes the future, not the flag.
            if let pullID = StewardRuleID.pullReportID(from: id) {
                return [.init("Acknowledge — inspected & resolved", .acknowledgePull(pullID)),
                        .init("Adjust operating envelope", .editEnvelope)]
            }
            if StewardRuleID.isLive(id) { return [.init("Adjust operating envelope", .editEnvelope)] }
            return []
        }
    }

    /// True when the observation has at least one concrete fix (so its row should be tappable).
    public static func isActionable(_ obs: StewardObservation, in vehicle: Vehicle) -> Bool {
        !options(for: obs, in: vehicle).isEmpty
    }
}
