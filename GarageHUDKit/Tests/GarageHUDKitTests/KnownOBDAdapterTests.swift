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

    func testAffordableBLEAdaptersHaveNamedUARTProfiles() {
        let veepeak = KnownOBDAdapter.veepeakOBDCheckBLE
        XCTAssertEqual(veepeak.serviceUUID, "FFF0")
        XCTAssertEqual(veepeak.notifyCharUUID, "FFF1")
        XCTAssertEqual(veepeak.writeCharUUID, "FFF2")

        let vgate = KnownOBDAdapter.vgateICarProBLE
        XCTAssertEqual(vgate.serviceUUID, "FFE0")
        XCTAssertEqual(vgate.notifyCharUUID, "FFE1")
        XCTAssertEqual(vgate.writeCharUUID, "FFE1")
        XCTAssertEqual(KnownOBDAdapter.knownBLEServiceUUIDs, ["FFE0", "FFF0"])
    }

    func testMatchPrefersMostSpecificName() {
        // "OBDLink MX+" contains both "OBDLink" (CX pattern) and "MX+" — the MX+ must win.
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "OBDLink MX+")?.id, "obdlink-mxplus")
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "OBDLink CX")?.id, "obdlink-cx")
    }

    func testMatchFallsToGenericCloneAndNilOnUnknown() {
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "Vgate vLinker")?.id, "elm327-ble")
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "VEEPEAK")?.id, "veepeak-obdcheck-ble")
        XCTAssertEqual(KnownOBDAdapter.match(advertisedName: "Vgate iCar Pro")?.id, "vgate-icar-pro-ble")
        XCTAssertNil(KnownOBDAdapter.match(advertisedName: "Kitchen Speaker"))
        XCTAssertNil(KnownOBDAdapter.match(advertisedName: nil))
    }

    func testHardwareSelectionMakesMXPlusLimitationExplicitAndPersists() {
        let suite = "OBDAdapterSelectionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(OBDAdapterSelectionStore.load(defaults: defaults), .obdLinkCX)
        XCTAssertTrue(OBDAdapterSelection.obdLinkCX.canConnectDirectly)
        XCTAssertTrue(OBDAdapterSelection.veepeakOBDCheckBLE.canConnectDirectly)
        XCTAssertTrue(OBDAdapterSelection.vgateICarProBLE.canConnectDirectly)
        XCTAssertFalse(OBDAdapterSelection.obdLinkMXPlus.canConnectDirectly)

        OBDAdapterSelectionStore.save(.obdLinkMXPlus, defaults: defaults)
        XCTAssertEqual(OBDAdapterSelectionStore.load(defaults: defaults), .obdLinkMXPlus)
    }

    func testSavedProfilesOnlyFollowTheSelectedNamedHardware() {
        let veepeak = OBDAdapterProfile(
            peripheralID: UUID(), name: "VEEPEAK", serviceUUID: "FFF0",
            writeCharUUID: "FFF2", notifyCharUUID: "FFF1", writeWithoutResponse: true)
        XCTAssertTrue(OBDAdapterSelection.veepeakOBDCheckBLE.acceptsSavedProfile(veepeak))
        XCTAssertTrue(OBDAdapterSelection.otherBLE.acceptsSavedProfile(veepeak))
        XCTAssertFalse(OBDAdapterSelection.obdLinkCX.acceptsSavedProfile(veepeak))
    }
}
