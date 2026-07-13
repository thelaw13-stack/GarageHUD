import XCTest
import CoreBluetooth
@testable import GarageHUDKit

/// The fresh-pairing scan is now unfiltered (many BLE OBD adapters omit their service UUID from the
/// advertisement), so the discovery filter must accept real adapters and reject unrelated devices.
final class OBDDiscoveryFilterTests: XCTestCase {
    private let serviceUUIDs = [CBUUID(string: "FFF0"), CBUUID(string: "FFE0")]

    private func likely(name: String?, uuids: [CBUUID] = []) -> Bool {
        OBDLiveDataSource.isLikelyOBDAdapter(advertisedName: name, advertisedServiceUUIDs: uuids,
                                             serviceUUIDs: serviceUUIDs)
    }

    func testAcceptsByAdvertisedServiceUUID() {
        // A generic clone with no useful name but advertising FFE0 still qualifies.
        XCTAssertTrue(likely(name: nil, uuids: [CBUUID(string: "FFE0")]))
    }

    func testAcceptsKnownAndObdNames() {
        XCTAssertTrue(likely(name: "OBDLink CX"))
        XCTAssertTrue(likely(name: "Vgate vLinker"))
        XCTAssertTrue(likely(name: "OBDII"))
        XCTAssertTrue(likely(name: "My OBD Reader"))   // any "obd" name
    }

    func testRejectsUnrelatedDevices() {
        XCTAssertFalse(likely(name: "AirPods Pro"))
        XCTAssertFalse(likely(name: "Kitchen Speaker"))
        XCTAssertFalse(likely(name: nil))              // nameless, no service → don't grab it
    }
}
