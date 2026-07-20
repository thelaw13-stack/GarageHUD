import Foundation

/// The whole-document sync bridge (W-054), now tombstone-aware (TD-001).
///
/// Last-writer-wins on a whole document means every concurrent edit is a coin flip where the
/// losing side's work lands in a snapshot the owner must notice. With live telemetry real, the
/// highest-value losers are exactly the records captured ON the car's phone — pulls, dyno results,
/// events, notes — while the Mac holds spec edits. So when adopting a remote document, append-only
/// records the local side holds are carried over instead of dropped.
///
/// Tombstones close the deletion half of that story. Each device records the ids it has deleted
/// (`Vehicle.deletedRecordIDs`); the merge unions both sides' tombstones and suppresses any record
/// they name, from either side. A delete therefore propagates instead of being undone by the other
/// side's held copy — the add-wins resurrection the earlier bridge documented as a known trade-off.
///
/// Deliberate scope limits, stated honestly:
/// - The vehicle SET is still adopt-side-wins (no deletion-resurrection of whole cars).
/// - Scalars, parts, and maintenance are still adopt-side-wins (they're *edited*, and picking
///   per-field winners without timestamps would be a guess wearing a merge's clothes).
/// - Same id on both sides → the adopting side's version wins (an edit race is still LWW).
/// - Delete-wins is deliberate for these capture-type records: a tombstone beats a concurrent
///   re-add of the same id. (UUIDs are unique per creation, so a "re-add" is only ever the other
///   device's stale copy, never a genuinely new record wanting the same id.)
/// - Honest residual limit: a deletion made by a client too old to write tombstones, or one lost
///   with the document it lived in, can't be honored — only real history (full event sync) closes
///   that, and it stays the TD-001 direction.
enum GarageMerge {

    /// The adopted remote garage, with local-only append records preserved and tombstoned records
    /// suppressed, per vehicle.
    static func adopt(_ remote: [Vehicle], preservingAppendsFrom local: [Vehicle]) -> [Vehicle] {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        return remote.map { adopted in
            guard let held = localByID[adopted.id] else { return adopted }
            var merged = adopted
            // A deletion recorded on either device wins over the other's still-held copy.
            let tombstones = adopted.deletedRecordIDs.union(held.deletedRecordIDs)
            merged.deletedRecordIDs = tombstones
            merged.pullReports = union(adopted.pullReports, held.pullReports, suppressing: tombstones)
            merged.performanceRecords = union(adopted.performanceRecords, held.performanceRecords, suppressing: tombstones)
            merged.buildEvents = union(adopted.buildEvents, held.buildEvents, suppressing: tombstones)
            merged.notes = union(adopted.notes, held.notes, suppressing: tombstones)
            merged.photos = union(adopted.photos, held.photos, suppressing: tombstones)
            // ADR-0005: edited state resolves by stamp instead of adopt-side-wins. Unstamped on both
            // sides is `.zero` vs `.zero`, which is not `>`, so the adopting side still wins and
            // legacy documents merge exactly as before.
            mergeGroups(into: &merged, adopted: adopted, held: held)
            merged.parts = mergeStamped(adopted.parts, held.parts, suppressing: tombstones)
            merged.maintenance = mergeStamped(adopted.maintenance, held.maintenance, suppressing: tombstones)
            return merged
        }
    }

    /// Resolve each coherence group as a unit. The group — never the field — is the unit of merge,
    /// so the result is always a state one device genuinely held for that group (ADR-0005 trap 2).
    private static func mergeGroups(into merged: inout Vehicle, adopted: Vehicle, held: Vehicle) {
        for group in CoherenceGroup.allCases where held.stamp(for: group) > adopted.stamp(for: group) {
            merged.adopt(group, from: held)
        }
    }

    /// Per-record resolution for edited collections.
    ///
    /// Records only one side has are kept (minus tombstones), so concurrent edits to *different*
    /// parts both survive — today one side's whole array loses. Records both sides hold resolve by
    /// stamp, with the adopting side keeping its version on a tie, preserving current behaviour for
    /// unstamped data. Ordering follows the adopting side, then local-only records, matching
    /// `union` so the two collections behave alike.
    private static func mergeStamped<T>(_ adopting: [T], _ localHeld: [T],
                                        suppressing tombstones: Set<UUID>) -> [T]
    where T: Identifiable, T.ID == UUID, T: Stamped {
        let heldByID = Dictionary(uniqueKeysWithValues: localHeld.map { ($0.id, $0) })
        let adoptedIDs = Set(adopting.map(\.id))
        let resolved = adopting.map { mine -> T in
            guard let theirs = heldByID[mine.id] else { return mine }
            return (theirs.stamp ?? .zero) > (mine.stamp ?? .zero) ? theirs : mine
        }
        let localOnly = localHeld.filter { !adoptedIDs.contains($0.id) }
        return (resolved + localOnly).filter { !tombstones.contains($0.id) }
    }

    /// Adopting side first (its versions win on id collisions), then local-only records — with any
    /// tombstoned id removed from the result, whichever side still carried it.
    private static func union<T: Identifiable>(_ adopting: [T], _ localHeld: [T],
                                               suppressing tombstones: Set<UUID>) -> [T] where T.ID == UUID {
        let have = Set(adopting.map(\.id))
        return (adopting + localHeld.filter { !have.contains($0.id) })
            .filter { !tombstones.contains($0.id) }
    }
}
