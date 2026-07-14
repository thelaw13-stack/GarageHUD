import XCTest
@testable import GarageHUDKit

/// Phase 2 — proactive between-visit nudges. The plan must include per-item maintenance reminders
/// plus a single calm fleet check-in, fire the check-in in the future, stay silent when nothing
/// warrants it, and honor the owner's toggle.
final class FleetWatchTests: XCTestCase {
    private func monthsAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .month, value: -n, to: .now)! }
    private func car(_ name: String, _ items: [MaintenanceItem] = [], review: Bool = false) -> Vehicle {
        var v = Vehicle(make: "M", model: name, year: 2020, nickname: name, garageSlot: 1)
        v.maintenance = items
        if review {   // a confirmed-stock gap on a boosted car → a non-informational observation
            v.factoryHorsepower = 200
            v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 400)]
            v.confirmedStockSystems = [.brakes]
            v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]
        }
        return v
    }

    func testNoCheckInWhenFleetIsHealthy() {
        let healthy = car("S2K", [MaintenanceItem(name: "Oil", intervalMonths: 24, lastServiced: monthsAgo(1))])
        XCTAssertNil(FleetWatch.checkIn(for: [healthy]))
    }

    func testCheckInLeadsWithTheMostUrgentCar() {
        let overdue = car("Fozzy", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))])
        let checkIn = FleetWatch.checkIn(for: [overdue])
        XCTAssertNotNil(checkIn)
        XCTAssertEqual(checkIn?.title, "Steward check-in")
        XCTAssertTrue(checkIn!.body.localizedCaseInsensitiveContains("fozzy"))
        XCTAssertTrue(checkIn!.body.localizedCaseInsensitiveContains("overdue"))
    }

    func testCheckInCountsOtherCarsNeedingAttention() {
        let a = car("A", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))])
        let b = car("B", [MaintenanceItem(name: "Brakes", intervalMonths: 6, lastServiced: monthsAgo(10))])
        let body = FleetWatch.checkIn(for: [a, b])!.body
        XCTAssertTrue(body.contains("1 other car"), body)
    }

    func testCheckInFiresInTheFutureAtTheCalmHour() {
        let overdue = car("Fozzy", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))])
        let now = Date()
        let checkIn = FleetWatch.checkIn(for: [overdue], now: now)!
        XCTAssertGreaterThan(checkIn.fireDate, now)
        let hour = Calendar.current.component(.hour, from: checkIn.fireDate)
        XCTAssertEqual(hour, FleetWatch.checkInHour)
    }

    func testPlanIncludesBothMaintenanceRemindersAndTheCheckIn() {
        let overdue = car("Fozzy", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))])
        let plan = FleetWatch.plan(for: [overdue])
        XCTAssertTrue(plan.contains { $0.id.hasPrefix("maint.") })
        XCTAssertTrue(plan.contains { $0.id == FleetWatch.checkInID })
    }

    func testDisablingCheckInsDropsItButKeepsMaintenance() {
        let overdue = car("Fozzy", [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: monthsAgo(12))])
        let plan = FleetWatch.plan(for: [overdue], checkInsEnabled: false)
        XCTAssertFalse(plan.contains { $0.id == FleetWatch.checkInID })
        XCTAssertTrue(plan.contains { $0.id.hasPrefix("maint.") })
    }

    func testReviewOnlyFleetStillEarnsACheckIn() {
        // No maintenance due, but a boosted car with a confirmed-stock brake gap → review item.
        let boosted = car("Track", review: true)
        let checkIn = FleetWatch.checkIn(for: [boosted])
        XCTAssertNotNil(checkIn)
        XCTAssertTrue(checkIn!.body.localizedCaseInsensitiveContains("worth a look"))
    }

    func testSettingsDefaultOnAndPersist() {
        let suite = "FleetWatchTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertTrue(FleetWatchSettings.isEnabled(d))       // default on
        FleetWatchSettings.setEnabled(false, d)
        XCTAssertFalse(FleetWatchSettings.isEnabled(d))
    }
}
