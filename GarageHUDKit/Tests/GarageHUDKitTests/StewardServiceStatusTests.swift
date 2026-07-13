import XCTest
@testable import GarageHUDKit

/// A car that's intentionally out of service (teardown/rebuild) is not neglected — Steward must
/// state the service status and suppress the quiet-build scolding, per-vehicle and fleet-wide.
final class StewardServiceStatusTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Calendar.current.date(byAdding: .day, value: offset, to: .now)! }

    private func longQuietCar(_ name: String, slot: Int) -> Vehicle {
        var v = Vehicle(make: "Honda", model: name, year: 2006, garageSlot: slot)
        v.nickname = name
        v.buildEvents = [BuildEvent(date: day(-400), title: "last touched")]  // 400 days → would be advisory
        return v
    }

    func testInServiceSuppressesQuietBuildAndStatesStatus() {
        var v = longQuietCar("S2K", slot: 1)
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown", since: day(-400))

        let obs = Steward.observe(v)
        XCTAssertFalse(obs.contains { $0.ruleID == "build.quiet" }, "a teardown isn't neglect")
        let svc = obs.first { $0.ruleID == "service.inService" }
        XCTAssertNotNil(svc)
        XCTAssertEqual(svc?.tone, .informational)
        XCTAssertTrue(svc!.evidence.localizedCaseInsensitiveContains("engine teardown"))
    }

    func testOperationalQuietCarStillGetsQuietBuild() {
        let obs = Steward.observe(longQuietCar("Fozzy", slot: 1))  // operational by default
        XCTAssertTrue(obs.contains { $0.ruleID == "build.quiet" })
        XCTAssertFalse(obs.contains { $0.ruleID == "service.inService" })
    }

    func testFleetNeglectSkipsInServiceCar() {
        var quiet = longQuietCar("S2K", slot: 1)
        quiet.serviceStatus = ServiceStatus(isInService: true, reason: "Teardown", since: day(-400))
        var active = Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 2)
        active.nickname = "Fozzy"
        active.buildEvents = [BuildEvent(date: day(-5), title: "fresh work")]

        // The only quiet car is in service → no fleet neglect claim.
        XCTAssertFalse(Steward.observeFleet([quiet, active]).contains { $0.ruleID == "fleet.neglect" })
    }

    func testChecklistProgressSurfacesInObservation() {
        var v = longQuietCar("S2K", slot: 1)
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Teardown", since: day(-100),
            checklist: [ServiceTask(title: "a", isDone: true), ServiceTask(title: "b"), ServiceTask(title: "c")])
        XCTAssertEqual(v.serviceStatus.progressText, "1 of 3 done")
        let svc = Steward.observe(v).first { $0.ruleID == "service.inService" }
        XCTAssertTrue(svc!.evidence.contains("1 of 3 done"))
    }

    func testMarkBackInServiceLogsEventAndResets() {
        var v = longQuietCar("S2K", slot: 1)
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown", since: day(-30),
            checklist: [ServiceTask(title: "a", isDone: true)])
        let eventsBefore = v.buildEvents.count

        v.markBackInService()

        XCTAssertFalse(v.serviceStatus.isInService)
        XCTAssertTrue(v.serviceStatus.checklist.isEmpty)
        XCTAssertEqual(v.buildEvents.count, eventsBefore + 1)
        let event = v.buildEvents.last!
        XCTAssertEqual(event.title, "Back in service")
        XCTAssertTrue(event.eventDescription.localizedCaseInsensitiveContains("engine teardown"))
        XCTAssertTrue(event.eventDescription.contains("30 days"))
        // And the Steward stops calling it out of service.
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID == "service.inService" })
    }

    func testMarkBackInServiceIsNoOpWhenOperational() {
        var v = longQuietCar("S2K", slot: 1)   // operational
        let before = v.buildEvents.count
        v.markBackInService()
        XCTAssertEqual(v.buildEvents.count, before)
    }

    func testServiceStatusDefaultsOperationalAndCodableRoundTrips() throws {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        XCTAssertFalse(v.serviceStatus.isInService)
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Rebuild", since: day(-10))
        let data = try GaragePersistence.encode([v])
        guard case .ok(let back) = GaragePersistence.decode(data) else { return XCTFail() }
        XCTAssertEqual(back[0].serviceStatus.reason, "Rebuild")
        XCTAssertTrue(back[0].serviceStatus.isInService)
    }
}
