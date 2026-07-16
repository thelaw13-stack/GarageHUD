import XCTest
@testable import GarageHUDKit

/// Temporal memory: comparing the last fleet snapshot against the fleet now must surface exactly the
/// changes worth a "since you were last here" greeting — service crossings, new dynos/pulls, miles,
/// parts — and stay silent when nothing meaningful moved.
final class FleetDigestTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    private func car(_ name: String) -> Vehicle {
        Vehicle(make: "M", model: name, year: 2020, nickname: name, garageSlot: 1)
    }

    func testFirstLaunchHasNoDigest() {
        XCTAssertNil(FleetDigestBuilder.digest(from: nil, to: [car("S2K")]))
    }

    func testNoChangesYieldsNilDigest() {
        let v = car("S2K")
        let snap = FleetDigestBuilder.snapshot(of: [v])
        XCTAssertNil(FleetDigestBuilder.digest(from: snap, to: [v]))
    }

    func testServiceWorseningSurfacesAsCautionThenAdvisory() {
        var v = car("Fozzy")
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: daysAgo(30))]  // ok now
        let before = FleetDigestBuilder.snapshot(of: [v])

        // Time passes: oil becomes overdue.
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: daysAgo(400))]
        let digest = FleetDigestBuilder.digest(from: before, to: [v])
        XCTAssertNotNil(digest)
        let change = digest!.changes.first { $0.kind == .serviceWorsened }
        XCTAssertNotNil(change)
        XCTAssertTrue(change!.text.localizedCaseInsensitiveContains("overdue"))
        XCTAssertEqual(change!.tone, .advisory)
    }

    func testNewDynoAndPullAndMilesAndPartsAreDetected() {
        var v = car("Tundra")
        v.buildEvents = [BuildEvent(date: daysAgo(10), title: "Odo", mileage: 40_000)]
        let before = FleetDigestBuilder.snapshot(of: [v])

        v.performanceRecords = [PerformanceRecord(date: daysAgo(1), type: .dyno, wheelHorsepower: 402)]
        v.pullReports = [samplePull()]
        v.buildEvents.append(BuildEvent(date: .now, title: "Drive", mileage: 40_650))   // +650 mi
        v.parts = [Part(name: "Leveling kit", category: .suspension, status: .installed)]

        let changes = FleetDigestBuilder.digest(from: before, to: [v])!.changes
        XCTAssertTrue(changes.contains { $0.kind == .dyno && $0.text.contains("402 whp") })
        XCTAssertTrue(changes.contains { $0.kind == .pull })
        XCTAssertTrue(changes.contains { $0.kind == .mileage && $0.text.contains("650") })
        XCTAssertTrue(changes.contains { $0.kind == .addedParts })
    }

    func testTinyMileageJitterIsIgnored() {
        var v = car("S2K")
        v.buildEvents = [BuildEvent(date: daysAgo(10), title: "a", mileage: 88_000)]
        let before = FleetDigestBuilder.snapshot(of: [v])
        v.buildEvents.append(BuildEvent(date: .now, title: "b", mileage: 88_003))   // +3 mi, below threshold
        XCTAssertNil(FleetDigestBuilder.digest(from: before, to: [v]))
    }

    func testServiceBayTransitionsBothWays() {
        var v = car("Baja")
        let out = FleetDigestBuilder.snapshot(of: [v])
        v.serviceStatus = ServiceStatus(isInService: true, reason: "teardown")
        XCTAssertTrue(FleetDigestBuilder.digest(from: out, to: [v])!.changes.contains { $0.kind == .wentIntoService })

        let inBay = FleetDigestBuilder.snapshot(of: [v])
        v.markBackInService()
        XCTAssertTrue(FleetDigestBuilder.digest(from: inBay, to: [v])!.changes.contains { $0.kind == .backInService })
    }

    func testAddedVehicleIsAnnounced() {
        let s2k = car("S2K")
        let before = FleetDigestBuilder.snapshot(of: [s2k])
        let digest = FleetDigestBuilder.digest(from: before, to: [s2k, car("Fozzy")])
        XCTAssertTrue(digest!.changes.contains { $0.kind == .addedVehicle && $0.text.contains("Fozzy") })
    }

    func testRemovedVehicleIsAnnounced() {
        let s2k = car("S2K")
        let fozzy = car("Fozzy")
        let before = FleetDigestBuilder.snapshot(of: [s2k, fozzy])
        let digest = FleetDigestBuilder.digest(from: before, to: [s2k])
        XCTAssertTrue(digest!.changes.contains { $0.kind == .removedVehicle && $0.text.contains("Fozzy") })
    }

    func testChangesAreOrderedMostSeriousFirst() {
        var v = car("Fozzy")
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: daysAgo(30))]
        v.buildEvents = [BuildEvent(date: daysAgo(10), title: "odo", mileage: 40_000)]
        let before = FleetDigestBuilder.snapshot(of: [v])

        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: daysAgo(400))]  // overdue → advisory
        v.buildEvents.append(BuildEvent(date: .now, title: "drive", mileage: 40_500))                  // miles → informational
        let changes = FleetDigestBuilder.digest(from: before, to: [v])!.changes
        XCTAssertEqual(changes.first?.tone, .advisory)   // the serious one leads
    }

    private func samplePull() -> PullReport {
        PullReport(startedAt: daysAgo(1).addingTimeInterval(-3), endedAt: daysAgo(1), feedLabel: "Simulated",
                   rpmStart: 3000, rpmPeak: 6500, rpmEnd: 6500, boostPeakPsi: 10, boostBreachedCeiling: false,
                   boostCeilingPsi: nil, onTargetFraction: nil, overTargetFraction: nil, underTargetFraction: nil,
                   coolantStartF: nil, coolantPeakF: nil, coolantDeltaF: nil, sampleCount: 6,
                   measuredBoostFraction: nil, confidence: .weak)
    }
}
