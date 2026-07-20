import Foundation

/// This device's stable sync identity and its clock, persisted across launches.
///
/// Both halves matter. A node id regenerated per launch would make the tiebreak meaningless and
/// could let one device appear as many. A clock that reset on launch would restart the counter at
/// zero, so an edit made right after opening the app could order *behind* an edit made before
/// closing it — the app would quietly lose the owner's newest work.
public enum SyncIdentity {

    private static let nodeKey = "GHUD.sync.nodeID.v1"
    private static let clockKey = "GHUD.sync.lastStamp.v1"

    /// Stable per-install id. Not a device fingerprint and never leaves the owner's own sync — it
    /// exists only to break ties deterministically, and carries no meaning beyond that.
    public static func nodeID(defaults: UserDefaults = .standard) -> UUID {
        if let raw = defaults.string(forKey: nodeKey), let id = UUID(uuidString: raw) { return id }
        let fresh = UUID()
        defaults.set(fresh.uuidString, forKey: nodeKey)
        return fresh
    }

    /// The clock, resumed from the highest reading this device has issued or observed.
    public static func loadClock(defaults: UserDefaults = .standard) -> SyncClock {
        let node = nodeID(defaults: defaults)
        let last = defaults.data(forKey: clockKey)
            .flatMap { try? JSONDecoder().decode(SyncStamp.self, from: $0) }
        return SyncClock(node: node, last: last)
    }

    public static func save(_ clock: SyncClock, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(clock.last) {
            defaults.set(data, forKey: clockKey)
        }
    }
}
