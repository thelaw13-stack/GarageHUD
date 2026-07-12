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
