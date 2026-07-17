import Foundation

/// One adapter surfaced by a scan, before the owner picks which to validate. Carries what's needed
/// to tell devices apart in a crowded garage — advertised name, signal, and the services it claims —
/// plus what the catalog knows about it, so a dead end (an MFi/Classic adapter that CoreBluetooth
/// can never open) is visible as such instead of an inviting tap.
public struct OBDAdapterCandidate: Identifiable, Sendable, Equatable, Codable {
    public var peripheralID: UUID
    public var name: String
    public var rssi: Int
    public var advertisedServiceUUIDs: [String]
    public var discoveredAt: Date

    public var id: UUID { peripheralID }

    public init(
        peripheralID: UUID,
        name: String,
        rssi: Int,
        advertisedServiceUUIDs: [String],
        discoveredAt: Date
    ) {
        self.peripheralID = peripheralID
        self.name = name
        self.rssi = rssi
        self.advertisedServiceUUIDs = advertisedServiceUUIDs
        self.discoveredAt = discoveredAt
    }

    /// The catalog entry this advertised name best matches, if any.
    public var known: KnownOBDAdapter? { KnownOBDAdapter.match(advertisedName: name) }

    /// False only for adapters our CoreBluetooth stack can't open (MFi/Bluetooth-Classic, e.g. the
    /// OBDLink MX+). Unknown/unbranded names are treated as reachable and inspected on connect.
    public var isReachableOverBLE: Bool { (known?.transport ?? .bluetoothLE) != .externalAccessory }

    /// Why a visible adapter can't be paired here — nil when it can.
    public var unreachableReason: String? {
        guard !isReachableOverBLE else { return nil }
        return known?.note ?? "This adapter uses Apple's MFi/Bluetooth-Classic route, which GarageHUD can't open."
    }

    /// The owner-facing adapter selection this candidate implies, so picking it also records *which*
    /// model was paired — a saved profile is only honored next launch when the stored selection
    /// accepts it (see `OBDAdapterSelection.acceptsSavedProfile`).
    public var impliedSelection: OBDAdapterSelection {
        switch known?.id {
        case "obdlink-cx": return .obdLinkCX
        case "veepeak-obdcheck-ble": return .veepeakOBDCheckBLE
        case "vgate-icar-pro-ble": return .vgateICarProBLE
        case "obdlink-mxplus": return .obdLinkMXPlus
        default: return .otherBLE
        }
    }
}

public enum OBDAdapterCandidateList {
    /// Add or refresh a candidate, keeping the list ordered for a picker: adapters we can actually
    /// open first (a Classic/MFi device is a dead end, so it sinks), then strongest signal — the
    /// honest discriminator for "which of these is the one in my car" — then name for stability.
    public static func upserting(_ candidate: OBDAdapterCandidate, into candidates: [OBDAdapterCandidate]) -> [OBDAdapterCandidate] {
        var next = candidates
        if let index = next.firstIndex(where: { $0.peripheralID == candidate.peripheralID }) {
            next[index] = candidate
        } else {
            next.append(candidate)
        }
        return next.sorted { lhs, rhs in
            if lhs.isReachableOverBLE != rhs.isReachableOverBLE { return lhs.isReachableOverBLE }
            if lhs.rssi != rhs.rssi { return lhs.rssi > rhs.rssi }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
