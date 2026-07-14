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

/// The hardware route the owner intends to use. Persisting the choice prevents the Live screen
/// from repeatedly launching a BLE search for an MX+, which iOS exposes through its accessory
/// route instead of CoreBluetooth.
public enum OBDAdapterSelection: String, CaseIterable, Sendable, Codable, Equatable, Identifiable {
    case obdLinkCX
    case veepeakOBDCheckBLE
    case vgateICarProBLE
    case obdLinkMXPlus
    case otherBLE

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .obdLinkCX: return "OBDLink CX"
        case .veepeakOBDCheckBLE: return "Veepeak OBDCheck BLE"
        case .vgateICarProBLE: return "Vgate iCar Pro BLE"
        case .obdLinkMXPlus: return "OBDLink MX+"
        case .otherBLE: return "Other BLE adapter"
        }
    }

    public var transport: OBDTransport {
        self == .obdLinkMXPlus ? .externalAccessory : .bluetoothLE
    }

    public var canConnectDirectly: Bool { transport == .bluetoothLE }

    public var setupDetail: String {
        switch self {
        case .obdLinkCX:
            return "GarageHUD can pair directly. Start the engine and close every other OBD app first."
        case .veepeakOBDCheckBLE:
            return "Connect inside GarageHUD, not in iPhone Bluetooth Settings. Unplug it if the car will sit for more than a week."
        case .vgateICarProBLE:
            return "Connect inside GarageHUD. Its automatic sleep mode makes it a practical leave-in adapter."
        case .obdLinkMXPlus:
            return "The iPhone can list this adapter, but GarageHUD cannot open its protected MFi data channel yet. OBDLink manufacturer access is required."
        case .otherBLE:
            return "GarageHUD will inspect OBD-named Bluetooth LE devices for an ELM327-compatible serial channel."
        }
    }

    public var knownAdapter: KnownOBDAdapter? {
        switch self {
        case .obdLinkCX: return .obdLinkCX
        case .veepeakOBDCheckBLE: return .veepeakOBDCheckBLE
        case .vgateICarProBLE: return .vgateICarProBLE
        case .obdLinkMXPlus: return .obdLinkMXPlus
        case .otherBLE: return nil
        }
    }

    public func acceptsSavedProfile(_ profile: OBDAdapterProfile) -> Bool {
        let matched = KnownOBDAdapter.match(advertisedName: profile.name)
        switch self {
        case .otherBLE:
            return matched?.transport != .externalAccessory
        default:
            return matched?.id == knownAdapter?.id
        }
    }
}

public enum OBDAdapterSelectionStore {
    private static let key = "GarageHUD.selectedOBDAdapter.v1"

    public static func load(defaults: UserDefaults = .standard) -> OBDAdapterSelection {
        guard let raw = defaults.string(forKey: key), let selection = OBDAdapterSelection(rawValue: raw) else {
            return .obdLinkCX
        }
        return selection
    }

    public static func save(_ selection: OBDAdapterSelection, defaults: UserDefaults = .standard) {
        defaults.set(selection.rawValue, forKey: key)
    }
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

    /// An inexpensive, standards-based BLE adapter with the same FFF0 UART layout as OBDLink CX.
    public static let veepeakOBDCheckBLE = KnownOBDAdapter(
        id: "veepeak-obdcheck-ble", displayName: "Veepeak OBDCheck BLE",
        nameMatches: ["Veepeak OBDCheck BLE", "OBDCheck BLE", "VEEPEAK"],
        transport: .bluetoothLE,
        serviceUUID: "FFF0", notifyCharUUID: "FFF1", writeCharUUID: "FFF2",
        note: "Bluetooth LE ELM327 — connect inside GarageHUD, not iPhone Bluetooth Settings.")

    /// Vgate's leave-in BLE adapter. Common firmware exposes a single FFE1 UART characteristic
    /// for both writes and notifications; dynamic discovery remains available if firmware differs.
    public static let vgateICarProBLE = KnownOBDAdapter(
        id: "vgate-icar-pro-ble", displayName: "Vgate iCar Pro BLE",
        nameMatches: ["Vgate iCar Pro", "iCar Pro", "Vgate", "IOS-Vlink"],
        transport: .bluetoothLE,
        serviceUUID: "FFE0", notifyCharUUID: "FFE1", writeCharUUID: "FFE1",
        note: "Bluetooth LE ELM327 with automatic sleep and wake.")

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

    public static let catalog: [KnownOBDAdapter] = [
        obdLinkCX, veepeakOBDCheckBLE, vgateICarProBLE, obdLinkMXPlus, genericELM327
    ]

    public static var knownBLEServiceUUIDs: [String] {
        Array(Set(catalog.filter(\.isBLE).compactMap(\.serviceUUID))).sorted()
    }

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
