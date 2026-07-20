import Foundation

/// A hybrid logical clock reading — the order of an edit, not the time of one.
///
/// ADR-0005. Device wall-clock time cannot decide a merge on its own: a phone running three minutes
/// fast would silently win every race against the Mac forever, and nothing in the record would show
/// it. So `physical` is used only as a *floor*. Every device adopts the highest stamp it observes
/// and advances past it, which means a fast clock buys one round of advantage, not permanent
/// victory.
///
/// A stamp never claims *when* anything happened and is never shown to the owner. `dateAdded`,
/// service dates, and record dates remain the human-facing truth. This orders edits; that is all.
public struct SyncStamp: Codable, Hashable, Sendable, Comparable {

    /// Milliseconds since 1970 — a floor, deliberately not a `Date`, so encoding is exact and
    /// comparison can't drift on sub-millisecond noise.
    public var millis: Int64
    /// Distinguishes edits sharing a millisecond, and carries the "ahead of local time" case.
    public var counter: UInt64
    /// Stable per-device id. Used only as the final deterministic tiebreak, never as a priority —
    /// no device is inherently more authoritative than another.
    public var node: UUID

    public init(millis: Int64, counter: UInt64, node: UUID) {
        self.millis = millis
        self.counter = counter
        self.node = node
    }

    /// "Unknown and oldest" — what an unstamped legacy value decodes to, so a deliberate edit from
    /// an upgraded client beats a value nobody has touched since before the upgrade.
    public static let zero = SyncStamp(millis: Int64.min, counter: 0,
                                       node: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)

    public var isZero: Bool { self == .zero }

    /// Total order: time, then counter, then node id. The node comparison exists so two devices
    /// merging the same pair independently reach the *same* answer — without it the result would
    /// depend on which side ran the merge.
    public static func < (a: SyncStamp, b: SyncStamp) -> Bool {
        if a.millis != b.millis { return a.millis < b.millis }
        if a.counter != b.counter { return a.counter < b.counter }
        return a.node.uuidString < b.node.uuidString
    }
}

/// Issues stamps for this device and folds in stamps observed from others.
///
/// Pure apart from the injected wall clock, matching the `now: Date = .now` pattern already used
/// throughout `Live/`, so skew and tie behaviour are testable without waiting on real time.
public struct SyncClock: Sendable {

    public let node: UUID
    /// The highest reading this device has issued or observed.
    public private(set) var last: SyncStamp

    public init(node: UUID, last: SyncStamp? = nil) {
        self.node = node
        self.last = last ?? SyncStamp(millis: Int64.min, counter: 0, node: node)
    }

    private static func millis(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded(.down))
    }

    /// Stamp a local edit. Advances past the last observed reading even when the wall clock hasn't
    /// moved (or has moved backwards, which a manual clock change can do).
    public mutating func stamp(now: Date = .now) -> SyncStamp {
        let wall = Self.millis(now)
        if wall > last.millis {
            last = SyncStamp(millis: wall, counter: 0, node: node)
        } else {
            last = SyncStamp(millis: last.millis, counter: last.counter + 1, node: node)
        }
        return last
    }

    /// Fold in a stamp seen from another device. This is what stops a fast clock winning forever:
    /// the peer adopts the higher reading, so its own next edit orders *after* it rather than
    /// behind it.
    public mutating func observe(_ remote: SyncStamp, now: Date = .now) {
        let wall = Self.millis(now)
        let ceiling = max(max(wall, remote.millis), last.millis)
        if ceiling == remote.millis && ceiling == last.millis {
            last = SyncStamp(millis: ceiling, counter: max(remote.counter, last.counter) + 1, node: node)
        } else if ceiling == remote.millis {
            last = SyncStamp(millis: ceiling, counter: remote.counter + 1, node: node)
        } else if ceiling == last.millis {
            last = SyncStamp(millis: ceiling, counter: last.counter + 1, node: node)
        } else {
            last = SyncStamp(millis: ceiling, counter: 0, node: node)
        }
    }
}

/// Fields that must move together, so a merge can never assemble a car that existed on no device.
///
/// ADR-0005 trap 2, and the reason this is not textbook field-level LWW: merging a Mac's
/// `factoryHorsepower` edit with a phone's `factoryPowerBasis` edit yields a crank figure wearing a
/// wheel label — two individually correct edits producing a vehicle neither owner ever saw. The
/// group is the unit of merge, so the whole group wins or loses as one.
public enum CoherenceGroup: String, Codable, CaseIterable, Sendable {
    /// make, model, year, trim, nickname, colorName, garageSlot
    case identity
    /// factoryHorsepower, factoryTorque, factoryPowerBasis, drivetrain, engineDescription
    case power
    /// purchasePrice, documentedTotalInvestment — never collapsed into one number (Constitution 4)
    case money
    /// serviceStatus: the flag and its reason are one fact
    case status
    /// factoryForcedInductionOverride, obd2Override, operatingEnvelopeOverride
    case capability
}

/// A record that carries its own edit ordering, so collections of them can be merged per record
/// rather than whole-array (ADR-0005 part 3).
public protocol Stamped {
    var stamp: SyncStamp? { get }
}

extension Part: Stamped {}
extension MaintenanceItem: Stamped {}
