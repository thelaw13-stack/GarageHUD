import Foundation

/// A validated OBD-II adapter the owner has successfully paired with. Persisting this is what
/// lets GarageHUD reconnect *only to a known device* instead of grabbing the first peripheral
/// that advertises a serial service — the review's correction for unsafe auto-connect.
///
/// It records exactly what's needed to reconnect deterministically: which peripheral, which
/// service, which characteristic pair (from the *same* service), and how to write.
public struct OBDAdapterProfile: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// CoreBluetooth peripheral identifier — stable per device+app install.
    public var peripheralID: UUID
    public var name: String
    public var serviceUUID: String
    public var writeCharUUID: String
    public var notifyCharUUID: String
    public var writeWithoutResponse: Bool
    public var lastConnected: Date?

    public var id: UUID { peripheralID }

    public init(peripheralID: UUID, name: String, serviceUUID: String,
                writeCharUUID: String, notifyCharUUID: String,
                writeWithoutResponse: Bool, lastConnected: Date? = nil) {
        self.peripheralID = peripheralID
        self.name = name
        self.serviceUUID = serviceUUID
        self.writeCharUUID = writeCharUUID
        self.notifyCharUUID = notifyCharUUID
        self.writeWithoutResponse = writeWithoutResponse
        self.lastConnected = lastConnected
    }
}

/// Small local memory for the last adapter that completed a real handshake. The
/// profile contains only CoreBluetooth routing data and is safe to keep in app preferences.
public enum OBDAdapterProfileStore {
    private static let key = "GarageHUD.validatedOBDAdapter.v1"

    public static func load(defaults: UserDefaults = .standard) -> OBDAdapterProfile? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OBDAdapterProfile.self, from: data)
    }

    public static func save(_ profile: OBDAdapterProfile, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key)
    }

    public static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }
}

/// How an adapter physically talks to iOS. Only `.bluetoothLE` adapters are reachable from our
/// CoreBluetooth stack; `.externalAccessory` (MFi / Bluetooth Classic) adapters require Apple's
/// ExternalAccessory framework + an MFi entitlement, which GarageHUD does not have.
public enum OBDTransport: String, Sendable, Codable, Equatable {
    case bluetoothLE
    case externalAccessory
}

/// A catalog entry for a known OBD adapter — its transport and, for BLE devices, the GATT UUIDs we
/// expect. Lets the app recognize a paired device by name, prefer a known-good adapter during a
/// fresh scan, and explain clearly when a device (like the MX+) can't be reached over BLE.
public struct KnownOBDAdapter: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    /// Substrings matched (case-insensitively) against the advertised peripheral name.
    public let nameMatches: [String]
    public let transport: OBDTransport
    public let serviceUUID: String?
    public let notifyCharUUID: String?
    public let writeCharUUID: String?
    /// One-line note surfaced in the UI (e.g. why an MFi device won't appear in a BLE scan).
    public let note: String?

    public var isBLE: Bool { transport == .bluetoothLE }

    /// OBDLink CX — the only OBDLink adapter that uses Bluetooth LE, so it's the one our
    /// CoreBluetooth stack can pair with. Exposes the standard FFF0 UART service.
    public static let obdLinkCX = KnownOBDAdapter(
        id: "obdlink-cx", displayName: "OBDLink CX",
        nameMatches: ["OBDLink CX", "OBDLink", "CX"],
        transport: .bluetoothLE,
        serviceUUID: "FFF0", notifyCharUUID: "FFF1", writeCharUUID: "FFF2",
        note: "Bluetooth LE — pairs directly with GarageHUD.")

    /// OBDLink MX+ — Apple MFi / Bluetooth Classic. Reachable only via the ExternalAccessory
    /// framework, which needs an MFi entitlement GarageHUD doesn't carry, so it won't appear in a
    /// BLE scan. Cataloged so the app can say why, and point the owner at the CX.
    public static let obdLinkMXPlus = KnownOBDAdapter(
        id: "obdlink-mxplus", displayName: "OBDLink MX+",
        nameMatches: ["OBDLink MX+", "OBDLink MX", "MX+"],
        transport: .externalAccessory,
        serviceUUID: nil, notifyCharUUID: nil, writeCharUUID: nil,
        note: "MFi/Bluetooth Classic — needs Apple's ExternalAccessory framework; not reachable over Bluetooth LE. Use the OBDLink CX for GarageHUD live data.")

    /// A generic ELM327 BLE clone — the common no-name adapters on the FFE0 service.
    public static let genericELM327 = KnownOBDAdapter(
        id: "elm327-ble", displayName: "ELM327 (BLE)",
        nameMatches: ["OBDII", "OBD2", "ELM327", "VLINK", "vLinker"],
        transport: .bluetoothLE,
        serviceUUID: "FFE0", notifyCharUUID: "FFE1", writeCharUUID: "FFE1",
        note: "Generic Bluetooth LE ELM327 clone.")

    public static let catalog: [KnownOBDAdapter] = [obdLinkCX, obdLinkMXPlus, genericELM327]

    /// The catalog entry whose name patterns best match an advertised peripheral name, if any.
    public static func match(advertisedName name: String?) -> KnownOBDAdapter? {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        let lower = name.lowercased()
        // Prefer the most specific match (longest matching substring) so "OBDLink MX+" beats "OBDLink".
        return catalog
            .compactMap { adapter -> (KnownOBDAdapter, Int)? in
                let best = adapter.nameMatches
                    .filter { lower.contains($0.lowercased()) }
                    .map(\.count).max()
                return best.map { (adapter, $0) }
            }
            .max { $0.1 < $1.1 }?.0
    }
}
