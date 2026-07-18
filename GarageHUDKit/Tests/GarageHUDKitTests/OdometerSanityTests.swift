import XCTest
@testable import GarageHUDKit

/// The odometer is the reasoning spine — one fat-fingered reading poisons current mileage, the
/// learned driving rate, and every mileage-based due state. Entry-time anomalies warn (never
/// block), and a record that already disagrees with itself is surfaced by the Steward instead of
/// silently reasoned on.
final class OdometerSanityTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Date(timeIntervalSinceNow: Double(offset) * 86_400) }

    private func truck(readings: [(Int, Int)]) -> Vehicle {   // (dayOffset, miles)
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = readings.map { BuildEvent(date: day($0.0), title: "Odometer", mileage: $0.1) }
        return v
    }

    // MARK: Entry-time validator

    func testUnremarkableReadingPassesQuietly() {
        let v = truck(readings: [(-30, 50_000)])
        XCTAssertNil(v.odometerAnomaly(proposing: 51_000, on: day(0)))
    }

    func testFirstReadingEverIsNeverFlagged() {
        let v = truck(readings: [])
        XCTAssertNil(v.odometerAnomaly(proposing: 580_000, on: day(0)), "no record to disagree with")
    }

    func testRegressionIsFlagged() {
        let v = truck(readings: [(-30, 58_000)])
        guard case .regression(let prior, _)? = v.odometerAnomaly(proposing: 51_000, on: day(0)) else {
            return XCTFail("a reading below the recorded 58,000 must flag")
        }
        XCTAssertEqual(prior, 58_000)
    }

    func testSlippedDigitIsFlaggedAsImplausibleRate() {
        // 50,000 → 580,000 in a month: the classic extra-zero typo.
        let v = truck(readings: [(-30, 50_000)])
        guard case .implausibleRate(let rate)? = v.odometerAnomaly(proposing: 580_000, on: day(0)) else {
            return XCTFail("an extra-zero typo must flag")
        }
        XCTAssertGreaterThan(rate, Vehicle.implausibleMilesPerDay)
    }

    func testRoadTripDayIsNotFlagged() {
        // 800 miles in a day is a real drive, not a typo.
        let v = truck(readings: [(-1, 50_000)])
        XCTAssertNil(v.odometerAnomaly(proposing: 50_800, on: day(0)))
    }

    func testBackdatedEntryComparesAgainstItsOwnEra() {
        // Record: 50,000 (60d ago), 58,000 (today). Backdating 54,000 to 30d ago is consistent
        // with its own era even though it's below today's reading.
        let v = truck(readings: [(-60, 50_000), (0, 58_000)])
        XCTAssertNil(v.odometerAnomaly(proposing: 54_000, on: day(-30)))
    }

    // MARK: Steward surfacing

    func testStewardSurfacesARecordThatDisagreesWithItself() {
        let v = truck(readings: [(-30, 58_000), (0, 51_000)])   // later date, lower reading
        let obs = Steward.observe(v).first { $0.ruleID == "data.odometerRegression" }
        XCTAssertNotNil(obs, "a self-contradictory odometer record must be surfaced")
        XCTAssertTrue(obs!.evidence.contains("51,000"), obs!.evidence)
        XCTAssertTrue(obs!.evidence.contains("58,000"), obs!.evidence)
    }

    func testConsistentRecordStaysQuiet() {
        let v = truck(readings: [(-60, 50_000), (-30, 54_000), (0, 58_000)])
        XCTAssertFalse(Steward.observe(v).contains { $0.ruleID == "data.odometerRegression" })
    }
}
