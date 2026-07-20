import Foundation

/// Stamps what the owner actually changed, by diffing a save against the state it replaced.
///
/// W-065. The alternative was stamping at every edit site, which is more visible but carries a
/// permanent forgetting hazard: a view added later that edits a field and never stamps it degrades
/// merges silently, and nothing fails. Diffing centrally means there is one place to be correct.
///
/// The cost, stated honestly: this infers intent from a value change rather than observing the edit.
/// A change made by normalization or healing rather than by the owner looks identical to a real
/// edit and will be stamped as one. That is acceptable because the stamp only orders edits — it
/// never claims the owner did anything — but it means stamping must run only on genuine local
/// saves, never while loading or applying a remote document.
public enum SyncStamper {

    /// Return `updated`, with a fresh stamp on every coherence group and every part/maintenance
    /// record whose values differ from `previous`.
    ///
    /// Unchanged things keep their existing stamp, so a save that changes nothing advances nothing —
    /// otherwise every launch would inflate stamps and the last device to open the app would win
    /// regardless of who actually edited.
    public static func stamping(_ updated: [Vehicle], against previous: [Vehicle],
                                clock: inout SyncClock, now: Date = .now) -> [Vehicle] {
        let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return updated.map { vehicle in
            // A vehicle that did not exist before needs no stamps: its id is unique to this device,
            // so there is nothing on the other side to resolve against.
            guard let old = before[vehicle.id] else { return vehicle }
            var stamped = vehicle

            for group in CoherenceGroup.allCases where !vehicle.groupMatches(group, old) {
                stamped.setStamp(clock.stamp(now: now), for: group)
            }

            stamped.parts = stampChanged(vehicle.parts, against: old.parts, clock: &clock, now: now)
            stamped.maintenance = stampChanged(vehicle.maintenance, against: old.maintenance,
                                               clock: &clock, now: now)
            return stamped
        }
    }

    /// Stamp records whose *values* changed. The comparison ignores the stamp field itself —
    /// otherwise stamping a record would make it differ from its predecessor and it would restamp
    /// on every save forever.
    private static func stampChanged<T>(_ updated: [T], against previous: [T],
                                        clock: inout SyncClock, now: Date) -> [T]
    where T: Identifiable, T.ID == UUID, T: Stampable {
        let before = Dictionary(uniqueKeysWithValues: previous.map { ($0.id, $0) })
        return updated.map { record in
            guard let old = before[record.id] else { return record }   // new record: nothing to resolve
            var probe = record
            probe.stamp = old.stamp
            guard probe != old else { return record }                  // genuinely unchanged
            var restamped = record
            restamped.stamp = clock.stamp(now: now)
            return restamped
        }
    }
}

/// A stamped record whose stamp can also be written — the diffing half of `Stamped`.
public protocol Stampable: Stamped, Equatable {
    var stamp: SyncStamp? { get set }
}

extension Part: Stampable {}
extension MaintenanceItem: Stampable {}
