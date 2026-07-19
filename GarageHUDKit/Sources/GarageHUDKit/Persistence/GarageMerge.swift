import Foundation

/// The whole-document sync bridge (W-054, Fable fix #3).
///
/// Last-writer-wins on a whole document means every concurrent edit is a coin flip where the
/// losing side's work lands in a snapshot the owner must notice. With live telemetry now real,
/// the highest-value losers are exactly the records captured ON the car's phone — pulls, dyno
/// results, events, notes — while the Mac holds spec edits. This merge is the conservative
/// middle path until event-based sync (TD-001, now promoted): when adopting a remote document,
/// append-only records the local side holds are carried over instead of dropped.
///
/// Deliberate scope limits, stated honestly:
/// - The vehicle SET is still adopt-side-wins (no deletion-resurrection of whole cars).
/// - Scalars, parts, and maintenance are still adopt-side-wins (they're *edited*, and picking
///   per-field winners without timestamps would be a guess wearing a merge's clothes).
/// - Same id on both sides → the adopting side's version wins (an edit race is still LWW).
/// - Known trade-off: a record deleted remotely but still held locally is re-added (add-wins
///   without tombstones). A resurrected event is visible and deletable again; a silently lost
///   driveway pull is neither. Event-based sync with tombstones is the real fix.
enum GarageMerge {

    /// The adopted remote garage, with local-only append-type records preserved per vehicle.
    static func adopt(_ remote: [Vehicle], preservingAppendsFrom local: [Vehicle]) -> [Vehicle] {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        return remote.map { adopted in
            guard let held = localByID[adopted.id] else { return adopted }
            var merged = adopted
            merged.pullReports = union(adopted.pullReports, held.pullReports)
            merged.performanceRecords = union(adopted.performanceRecords, held.performanceRecords)
            merged.buildEvents = union(adopted.buildEvents, held.buildEvents)
            merged.notes = union(adopted.notes, held.notes)
            merged.photos = union(adopted.photos, held.photos)
            return merged
        }
    }

    /// Adopting side first (its versions win on id collisions), then local-only records.
    private static func union<T: Identifiable>(_ adopting: [T], _ localHeld: [T]) -> [T] where T.ID == UUID {
        let have = Set(adopting.map(\.id))
        return adopting + localHeld.filter { !have.contains($0.id) }
    }
}
