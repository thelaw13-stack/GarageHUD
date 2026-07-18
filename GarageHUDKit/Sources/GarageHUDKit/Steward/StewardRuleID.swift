import Foundation

/// The Steward's deterministic rule identities, defined once.
///
/// Rule ids are load-bearing strings: `StewardResolution` routes "Mark serviced" / "Confirm
/// stock" buttons by parsing them, and `NextStep` branches on them. When emitters minted ids
/// with inline literals ("gap.\(category.rawValue)") and parsers re-derived the format with
/// prefix surgery, a format change on either side broke the other silently. Every emitter and
/// parser now shares these builders, so the format cannot drift between the rule that mints an
/// id and the resolution that routes it.
public enum StewardRuleID {

    // MARK: Fixed ids

    public static let sequenceFIAheadOfFueling = "sequence.fiAheadOfFueling"
    public static let tuneStale = "tune.stale"
    public static let dynoPlateau = "dyno.plateau"
    public static let serviceInService = "service.inService"
    public static let buildQuiet = "build.quiet"
    public static let dataUndatedParts = "data.undatedParts"
    public static let dataOdometerRegression = "data.odometerRegression"
    // efficiency.costPerHp was retired in W-046: a statistic is not a task, so cost-per-hp is
    // a Specs/grounding figure, not an observation.
    public static let fleetValueLeader = "fleet.valueLeader"
    public static let fleetNeglect = "fleet.neglect"
    public static let liveCoolantCritical = "live.coolantCritical"
    public static let liveCoolantCaution = "live.coolantCaution"
    public static let liveBoostCeiling = "live.boostCeiling"
    public static let liveBoostOverTarget = "live.boostOverTarget"
    public static let liveBoostUnderTarget = "live.boostUnderTarget"
    public static let liveBoost = "live.boost"

    // MARK: Parameterized ids — builder and parser side by side, one format

    public static func gap(_ category: PartCategory) -> String { "gap.\(category.rawValue)" }
    public static func gapCategory(from id: String) -> PartCategory? {
        guard id.hasPrefix("gap.") else { return nil }
        return PartCategory(rawValue: String(id.dropFirst("gap.".count)))
    }

    public static func maintenanceOverdue(_ item: UUID) -> String { "maintenance.overdue.\(item.uuidString)" }
    public static func maintenanceDueSoon(_ item: UUID) -> String { "maintenance.dueSoon.\(item.uuidString)" }
    public static func isMaintenanceOverdue(_ id: String) -> Bool { id.hasPrefix("maintenance.overdue.") }
    public static func isMaintenanceDueSoon(_ id: String) -> Bool { id.hasPrefix("maintenance.dueSoon.") }
    public static func isMaintenance(_ id: String) -> Bool { id.hasPrefix("maintenance.") }
    public static func maintenanceItemID(from id: String) -> UUID? {
        id.split(separator: ".").last.flatMap { UUID(uuidString: String($0)) }
    }

    public static func fleetSharedGap(_ category: PartCategory) -> String { "fleet.sharedGap.\(category.rawValue)" }
    public static func pullFlagged(_ pull: UUID) -> String { "live.pullFlagged.\(pull.uuidString)" }

    public static func isLive(_ id: String) -> Bool { id.hasPrefix("live.") }
    public static func isGap(_ id: String) -> Bool { id.hasPrefix("gap.") }
}
