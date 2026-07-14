import XCTest
@testable import GarageHUDKit

final class ServiceCorrectionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func vehicle() -> Vehicle {
        var vehicle = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        vehicle.buildEvents = [BuildEvent(date: base, title: "Odometer", mileage: 40_000)]
        vehicle.maintenance = [MaintenanceItem(
            name: "Tire rotation", intervalMonths: 6,
            lastServiced: base.addingTimeInterval(-100 * 86_400),
            intervalMiles: 5_000, lastServicedMileage: 35_000)]
        return vehicle
    }

    func testUndoFirstServiceRestoresOriginalBaseline() {
        var vehicle = vehicle()
        let itemID = vehicle.maintenance[0].id
        let originalDate = vehicle.maintenance[0].lastServiced

        XCTAssertTrue(vehicle.markMaintenanceDone(itemID, on: base.addingTimeInterval(60)))
        let eventID = vehicle.serviceLog[0].id
        XCTAssertEqual(vehicle.maintenance[0].lastServicedMileage, 40_000)

        XCTAssertTrue(vehicle.removeServiceRecord(eventID))
        XCTAssertTrue(vehicle.serviceLog.isEmpty)
        XCTAssertEqual(vehicle.maintenance[0].lastServiced, originalDate)
        XCTAssertEqual(vehicle.maintenance[0].lastServicedMileage, 35_000)
    }

    func testUndoLatestServiceRollsBackToPriorRealService() {
        var vehicle = vehicle()
        let itemID = vehicle.maintenance[0].id
        let firstDate = base.addingTimeInterval(60)
        XCTAssertTrue(vehicle.markMaintenanceDone(itemID, on: firstDate))

        vehicle.buildEvents.append(BuildEvent(
            date: base.addingTimeInterval(120), title: "Odometer", mileage: 45_000))
        let secondDate = base.addingTimeInterval(180)
        XCTAssertTrue(vehicle.markMaintenanceDone(itemID, on: secondDate))
        let latestID = vehicle.serviceLog[0].id

        XCTAssertTrue(vehicle.removeServiceRecord(latestID))
        XCTAssertEqual(vehicle.serviceLog.count, 1)
        XCTAssertEqual(vehicle.maintenance[0].lastServiced, firstDate)
        XCTAssertEqual(vehicle.maintenance[0].lastServicedMileage, 40_000)
    }

    func testDeletingMiddleFalseRecordNeverResurrectsItLater() {
        var vehicle = vehicle()
        let itemID = vehicle.maintenance[0].id
        let originalDate = vehicle.maintenance[0].lastServiced

        XCTAssertTrue(vehicle.markMaintenanceDone(itemID, on: base.addingTimeInterval(60)))
        let firstID = vehicle.serviceLog[0].id
        vehicle.buildEvents.append(BuildEvent(
            date: base.addingTimeInterval(120), title: "Odometer", mileage: 45_000))
        XCTAssertTrue(vehicle.markMaintenanceDone(itemID, on: base.addingTimeInterval(180)))
        let secondID = vehicle.serviceLog[0].id

        XCTAssertTrue(vehicle.removeServiceRecord(firstID))
        XCTAssertTrue(vehicle.removeServiceRecord(secondID))
        XCTAssertTrue(vehicle.serviceLog.isEmpty)
        XCTAssertEqual(vehicle.maintenance[0].lastServiced, originalDate)
        XCTAssertEqual(vehicle.maintenance[0].lastServicedMileage, 35_000)
    }

    func testLegacyUnlinkedHistoryCanStillBeRemovedAndRecalculated() {
        var vehicle = vehicle()
        let old = BuildEvent(
            date: base.addingTimeInterval(60),
            title: "\(Vehicle.servicePrefix)Tire rotation @ 40,000 mi",
            mileage: 40_000)
        let latest = BuildEvent(
            date: base.addingTimeInterval(120),
            title: "\(Vehicle.servicePrefix)Tire rotation @ 45,000 mi",
            mileage: 45_000)
        vehicle.buildEvents.append(contentsOf: [old, latest])
        vehicle.maintenance[0].lastServiced = latest.date
        vehicle.maintenance[0].lastServicedMileage = latest.mileage

        XCTAssertTrue(vehicle.removeServiceRecord(latest.id))
        XCTAssertEqual(vehicle.maintenance[0].lastServiced, old.date)
        XCTAssertEqual(vehicle.maintenance[0].lastServicedMileage, old.mileage)
    }

    func testNonServiceEventCannotBeRemovedThroughServiceCorrection() {
        var vehicle = vehicle()
        let odometerID = vehicle.buildEvents[0].id
        XCTAssertFalse(vehicle.removeServiceRecord(odometerID))
        XCTAssertTrue(vehicle.buildEvents.contains { $0.id == odometerID })
    }

    func testServiceRollbackLinkSurvivesCoding() throws {
        var vehicle = vehicle()
        let itemID = vehicle.maintenance[0].id
        XCTAssertTrue(vehicle.markMaintenanceDone(itemID, on: base.addingTimeInterval(60)))

        let data = try JSONEncoder().encode(vehicle)
        let decoded = try JSONDecoder().decode(Vehicle.self, from: data)

        XCTAssertEqual(decoded.serviceLog[0].serviceRecord?.maintenanceItemID, itemID)
        XCTAssertEqual(decoded.serviceLog[0].serviceRecord?.previousServicedMileage, 35_000)
    }
}
