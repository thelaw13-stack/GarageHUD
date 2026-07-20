import Foundation

/// Reading and moving whole coherence groups (ADR-0005).
///
/// The group — not the field — is the unit of merge. Everything here moves every field of a group
/// together, so a merged vehicle is always a state some device genuinely held for that group. If a
/// field is added to a group's list in the ADR, it must be added to `adopt` below, or the merge
/// will silently keep a stale half of the group and reintroduce exactly the incoherence the design
/// exists to prevent.
public extension Vehicle {

    /// The stamp for a group, or `.zero` when this document predates stamping.
    func stamp(for group: CoherenceGroup) -> SyncStamp {
        groupStamps[group.rawValue] ?? .zero
    }

    /// Record that this device edited a group. Callers pass a stamp from their `SyncClock`.
    mutating func setStamp(_ stamp: SyncStamp, for group: CoherenceGroup) {
        groupStamps[group.rawValue] = stamp
    }

    /// Whether every field of `group` already matches `other`.
    ///
    /// Deliberately defined in terms of `adopt` rather than by listing the fields a second time: if
    /// adopting the group from `other` changes nothing, the groups are equal. Adding a field to a
    /// group therefore updates both behaviours at once, and the two can never drift apart — a
    /// hand-written second list is exactly how a field ends up merged but never detected as edited.
    func groupMatches(_ group: CoherenceGroup, _ other: Vehicle) -> Bool {
        var probe = self
        probe.adopt(group, from: other)
        probe.groupStamps = groupStamps      // adopt carries the stamp across; compare values only
        return probe == self
    }

    /// Take every field of `group` from `other`, together with its stamp.
    ///
    /// Deliberately exhaustive over `CoherenceGroup` with no `default:` — adding a case forces this
    /// switch to be updated rather than silently doing nothing for the new group.
    mutating func adopt(_ group: CoherenceGroup, from other: Vehicle) {
        switch group {
        case .identity:
            make = other.make
            model = other.model
            year = other.year
            trim = other.trim
            nickname = other.nickname
            colorName = other.colorName
            garageSlot = other.garageSlot
        case .power:
            factoryHorsepower = other.factoryHorsepower
            factoryTorque = other.factoryTorque
            factoryPowerBasis = other.factoryPowerBasis
            drivetrain = other.drivetrain
            engineDescription = other.engineDescription
        case .money:
            purchasePrice = other.purchasePrice
            documentedTotalInvestment = other.documentedTotalInvestment
        case .status:
            serviceStatus = other.serviceStatus
        case .capability:
            factoryForcedInductionOverride = other.factoryForcedInductionOverride
            obd2Override = other.obd2Override
            operatingEnvelopeOverride = other.operatingEnvelopeOverride
        }
        groupStamps[group.rawValue] = other.stamp(for: group)
    }
}
