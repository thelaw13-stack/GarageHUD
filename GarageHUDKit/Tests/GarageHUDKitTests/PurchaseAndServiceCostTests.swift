import XCTest
@testable import GarageHUDKit

/// Purchase price (acquisition) and service spend (maintenance) are two money facts kept deliberately
/// separate from build/mod investment — never conflated. These lock that separation in.
final class PurchaseAndServiceCostTests: XCTestCase {

    func testPurchasePriceRoundTripsAndDoesNotTouchTotalInvested() throws {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.parts = [Part(name: "Tonneau cover", category: .exterior, status: .installed, cost: 900)]
        v.purchasePrice = 60_000
        XCTAssertEqual(v.totalInvested, 900)          // build spend only — purchase price stays out
        XCTAssertEqual(v.purchasePrice, 60_000)

        let restored = try JSONDecoder().decode(Vehicle.self, from: JSONEncoder().encode(v))
        XCTAssertEqual(restored.purchasePrice, 60_000)
        XCTAssertEqual(restored.totalInvested, 900)   // still separate after a round-trip
    }

    func testPurchasePriceDecodesNilFromOlderFileWithoutTheKey() throws {
        // A garage file written before purchasePrice existed must still decode (missing key -> nil).
        let json = #"{"make":"Honda","model":"S2000","year":2004,"garageSlot":1}"#
        let v = try JSONDecoder().decode(Vehicle.self, from: Data(json.utf8))
        XCTAssertNil(v.purchasePrice)
    }

    func testServiceSpendSumsRecordedServiceCosts() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [
            BuildEvent(title: "\(Vehicle.servicePrefix)Oil change", serviceRecord: nil, cost: 89),
            BuildEvent(title: "\(Vehicle.servicePrefix)Tire rotation", serviceRecord: nil, cost: 40),
            BuildEvent(title: "\(Vehicle.servicePrefix)Inspection", serviceRecord: nil, cost: nil),  // unpriced
            BuildEvent(title: "Installed a light bar", cost: 350),                                    // not a service
        ]
        XCTAssertEqual(v.serviceSpend, 129)        // 89 + 40; unpriced and non-service excluded
        XCTAssertEqual(v.totalInvested, 0)         // service spend never leaks into build investment
    }

    func testMarkMaintenanceDoneCarriesCostOntoTheServiceRecord() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: .distantPast)]
        let id = v.maintenance[0].id
        XCTAssertTrue(v.markMaintenanceDone(id, cost: 89))
        XCTAssertEqual(v.serviceSpend, 89)
        XCTAssertEqual(v.latestServiceRecord(for: id)?.cost, 89)
    }

    func testSetBuildEventCostPricesAndClearsARecordAfterTheFact() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.maintenance = [MaintenanceItem(name: "Tires", intervalMonths: 12, lastServiced: .distantPast)]
        v.markMaintenanceDone(v.maintenance[0].id)          // logged with no cost
        let eventID = v.serviceLog.first!.id
        XCTAssertEqual(v.serviceSpend, 0)

        XCTAssertTrue(v.setBuildEventCost(eventID, 149))
        XCTAssertEqual(v.serviceSpend, 149)
        XCTAssertTrue(v.setBuildEventCost(eventID, nil))    // clear it
        XCTAssertEqual(v.serviceSpend, 0)
        XCTAssertFalse(v.setBuildEventCost(UUID(), 10))     // unknown id
    }
}
