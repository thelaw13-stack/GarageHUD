import XCTest
@testable import GarageHUDKit

/// The pairing picker's list logic. The first two cases come from the original scan-first picker
/// work; the rest cover what the `KnownOBDAdapter` catalog made possible afterwards — chiefly that
/// an MFi/Classic adapter is shown as a dead end rather than an inviting tap.
final class OBDAdapterCandidateTests: XCTestCase {

    private func candidate(_ name: String, rssi: Int, id: UUID = UUID(),
                           services: [String] = ["FFF0"]) -> OBDAdapterCandidate {
        OBDAdapterCandidate(peripheralID: id, name: name, rssi: rssi,
                            advertisedServiceUUIDs: services, discoveredAt: Date())
    }

    func testCandidateListSortsByStrongestSignal() {
        let weak = candidate("Weak", rssi: -80)
        let strong = candidate("Strong", rssi: -45)

        let candidates = OBDAdapterCandidateList.upserting(strong, into: OBDAdapterCandidateList.upserting(weak, into: []))

        XCTAssertEqual(candidates.map(\.name), ["Strong", "Weak"])
    }

    func testCandidateListUpdatesExistingPeripheral() {
        let id = UUID()
        let first = OBDAdapterCandidate(peripheralID: id, name: "OBD-II Adapter", rssi: -70,
                                        advertisedServiceUUIDs: ["FFE0"],
                                        discoveredAt: Date(timeIntervalSince1970: 1))
        let updated = OBDAdapterCandidate(peripheralID: id, name: "Veepeak OBDCheck BLE", rssi: -40,
                                          advertisedServiceUUIDs: ["FFE0"],
                                          discoveredAt: Date(timeIntervalSince1970: 2))

        let candidates = OBDAdapterCandidateList.upserting(updated, into: OBDAdapterCandidateList.upserting(first, into: []))

        XCTAssertEqual(candidates.count, 1)                       // same peripheral, refreshed
        XCTAssertEqual(candidates.first?.name, "Veepeak OBDCheck BLE")
        XCTAssertEqual(candidates.first?.rssi, -40)
    }

    // The MX+ is MFi/Bluetooth-Classic: iOS can list it, but CoreBluetooth can never open it.
    func testMFiAdapterIsMarkedUnreachableWithAReason() {
        let mxPlus = candidate("OBDLink MX+", rssi: -40)
        XCTAssertFalse(mxPlus.isReachableOverBLE)
        XCTAssertNotNil(mxPlus.unreachableReason)
        XCTAssertTrue(mxPlus.unreachableReason!.localizedCaseInsensitiveContains("classic")
                        || mxPlus.unreachableReason!.localizedCaseInsensitiveContains("mfi"))
    }

    func testUnreachableAdapterSinksBelowReachableOnesEvenWithAStrongerSignal() {
        let mxPlus = candidate("OBDLink MX+", rssi: -35)      // strongest, but a dead end
        let cx = candidate("OBDLink CX", rssi: -75)           // weak, but actually pairable
        var list = OBDAdapterCandidateList.upserting(mxPlus, into: [])
        list = OBDAdapterCandidateList.upserting(cx, into: list)

        XCTAssertEqual(list.map(\.name), ["OBDLink CX", "OBDLink MX+"])
    }

    func testUnbrandedAdapterIsTreatedAsReachableAndInspectedOnConnect() {
        let generic = candidate("OBDII", rssi: -60, services: ["FFE0"])
        XCTAssertTrue(generic.isReachableOverBLE)
        XCTAssertNil(generic.unreachableReason)
    }

    // Picking a candidate must also record *which model* was paired — a saved profile is only
    // honored next launch when the stored selection accepts it.
    func testImpliedSelectionMatchesTheCatalogSoASavedProfileIsAcceptedNextLaunch() {
        XCTAssertEqual(candidate("OBDLink CX", rssi: -50).impliedSelection, .obdLinkCX)
        XCTAssertEqual(candidate("Veepeak OBDCheck BLE", rssi: -50).impliedSelection, .veepeakOBDCheckBLE)
        XCTAssertEqual(candidate("Vgate iCar Pro", rssi: -50).impliedSelection, .vgateICarProBLE)
        XCTAssertEqual(candidate("Some Random ELM", rssi: -50).impliedSelection, .otherBLE)

        // The end-to-end contract: pair a Veepeak, and its selection accepts that profile.
        let veepeak = candidate("Veepeak OBDCheck BLE", rssi: -50)
        let profile = OBDAdapterProfile(peripheralID: veepeak.peripheralID, name: veepeak.name,
                                        serviceUUID: "FFF0", writeCharUUID: "FFF2",
                                        notifyCharUUID: "FFF1", writeWithoutResponse: true)
        XCTAssertTrue(veepeak.impliedSelection.acceptsSavedProfile(profile))
    }
}
