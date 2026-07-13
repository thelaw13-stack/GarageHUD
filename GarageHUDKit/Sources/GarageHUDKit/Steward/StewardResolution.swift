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

        if id.hasPrefix("maintenance.overdue."), let item = maintenanceID(id) {
            return [.init("Mark serviced", .markServiced(item)),
                    .init("Adjust interval…", .editSchedule(item))]
        }
        if id.hasPrefix("maintenance.dueSoon."), let item = maintenanceID(id) {
            return [.init("Mark serviced", .markServiced(item)),
                    .init("Adjust interval…", .editSchedule(item))]
        }
        if id == "service.inService" {
            return [.init("Mark back in service", .markBackInService)]
        }
        if id.hasPrefix("gap."), let cat = PartCategory(rawValue: String(id.dropFirst("gap.".count))) {
            return [.init("Confirm \(cat.rawValue.lowercased()) is factory-stock", .confirmStock(cat)),
                    .init("Add the \(cat.rawValue.lowercased()) part", .addPart(cat))]
        }
        switch id {
        case "tune.stale", "dyno.plateau", "efficiency.costPerHp":
            return [.init("Log a dyno result", .logPerformance)]
        case "build.quiet", "fleet.neglect":
            return [.init("Log recent work", .logActivity)]
        case "data.undatedParts", "sequence.fiAheadOfFueling":
            return [.init("Review parts", .reviewParts)]
        default:
            if id.hasPrefix("live.") { return [.init("Adjust operating envelope", .editEnvelope)] }
            return []
        }
    }

    /// True when the observation has at least one concrete fix (so its row should be tappable).
    public static func isActionable(_ obs: StewardObservation, in vehicle: Vehicle) -> Bool {
        !options(for: obs, in: vehicle).isEmpty
    }

    /// The maintenance item UUID embedded in a `maintenance.*.<uuid>` rule id.
    static func maintenanceID(_ ruleID: String) -> UUID? {
        ruleID.split(separator: ".").last.flatMap { UUID(uuidString: String($0)) }
    }
}
