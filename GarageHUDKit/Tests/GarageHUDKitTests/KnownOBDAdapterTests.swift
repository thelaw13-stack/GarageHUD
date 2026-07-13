import XCTest
@testable import GarageHUDKit

/// The adapter catalog recognizes known OBD hardware by advertised name and records how each one
/// talks to iOS — so the app targets the BLE-capable OBDLink CX and can explain why the MFi MX+
/// won't appear in a Bluetooth LE scan.
final class KnownOBDAdapterTests: XCTestCase {
    func testCXIsBLEWithStandardUARTUUIDs() {
        let cx = KnownOBDAdapter.obdLinkCX
        XCTAssertEqual(cx.transport, .bluetoothLE)
        XCTAssertTrue(cx.isBLE)
        XCTAssertEqual(cx.serviceUUID, "FFF0")
        XCTAssertEqual(cx.notifyCharUUID, "FFF1")
        XCTAssertEqual(cx.writeCharUUID, "FFF2")
    }

    func testMXPlusIsExternalAccessoryAndNotBLE() {
        let mx = KnownOBDAdapter.obdLinkMXPlus
        XCTAssertEqual(mx.transport, .externalAccessory)
        XCTAssertFalse(mx.isBLE)                 // can't be reached by our CoreBluetooth stack
        XCTAssertNil(mx.serviceUUID)
    }

    func testMatchPrefersMostSpecificName() {
        // "OBDLink MX+" contains both "OBDLink" (CX pattern) and "MX+" — the MX+ must win.
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "OBDLink MX+")?.id, "obdlink-mxplus")
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "OBDLink CX")?.id, "obdlink-cx")
    }

    func testMatchFallsToGenericCloneAndNilOnUnknown() {
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "Vgate vLinker")?.id, "elm327-ble")
        XCTAssertNil(KnownOBDAdapter.match(advertisedName: "Kitchen Speaker"))
        XCTAssertNil(KnownOBDAdapter.match(advertisedName: nil))
    }
}
