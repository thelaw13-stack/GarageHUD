import XCTest
@testable import GarageHUDKit

/// Wheel horsepower is a reasoning spine — one fat-fingered dyno figure poisons `hasMeasuredPower`,
/// the "N whp measured" headline, gain-over-stock, cost-per-hp, and the LLM grounding line. Like the
/// odometer, an implausible entry warns (never blocks). These tests lock the entry-time validator and
/// pin the exact honesty leak it exists to catch: an absurd figure stated as measured fact.
final class DynoSanityTests: XCTestCase {

    private func car(factoryHP: Double? = 200, dyno whp: Double?) -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "WRX", year: 2015, garageSlot: 1)
        v.factoryHorsepower = factoryHP
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: whp)]
        return v
    }

    // MARK: Entry-time validator

    func testRealisticFigurePassesQuietly() {
        XCTAssertNil(Vehicle.dynoAnomaly(proposingWheelHorsepower: 477))
        XCTAssertNil(Vehicle.dynoAnomaly(proposingWheelHorsepower: 1_500), "a big-but-real build is not a typo")
    }

    func testNothingEnteredIsNotAnAnomaly() {
        XCTAssertNil(Vehicle.dynoAnomaly(proposingWheelHorsepower: nil))
    }

    func testImplausiblyHighFigureIsFlagged() {
        guard case .implausiblyHigh(let whp)? = Vehicle.dynoAnomaly(proposingWheelHorsepower: 5_000) else {
            return XCTFail("5,000 whp must flag as a likely slipped digit")
        }
        XCTAssertEqual(whp, 5_000)
    }

    func testSlippedDigitIsFlagged() {
        // "477" typed as "4770" on the decimal pad — the canonical fat-finger.
        guard case .implausiblyHigh? = Vehicle.dynoAnomaly(proposingWheelHorsepower: 4_770) else {
            return XCTFail("4,770 whp must flag")
        }
    }

    func testCeilingBoundary() {
        XCTAssertNil(Vehicle.dynoAnomaly(proposingWheelHorsepower: 2_000), "at the ceiling is still allowed")
        guard case .implausiblyHigh? = Vehicle.dynoAnomaly(proposingWheelHorsepower: 2_001) else {
            return XCTFail("just over the ceiling must flag")
        }
    }

    func testNonPositiveIsNotAMeasurement() {
        XCTAssertEqual(Vehicle.dynoAnomaly(proposingWheelHorsepower: 0), .notPositive)
        XCTAssertEqual(Vehicle.dynoAnomaly(proposingWheelHorsepower: -50), .notPositive)
    }

    func testCautionsAreOwnerFacingAndNonBlocking() {
        // Copy matters: the caution invites a save ("or save if it's real"), never forbids it.
        XCTAssertTrue(DynoAnomaly.implausiblyHigh(whp: 5_000).caution.contains("save if it's real"))
        XCTAssertFalse(DynoAnomaly.notPositive.caution.isEmpty)
    }

    // MARK: The leak this guards — an absurd figure stated as measured fact

    func testAbsurdDynoWouldPoisonEveryMeasuredSurface() {
        // Before this guard, nothing screened an implausible figure: it flowed through as "measured".
        let v = car(dyno: 5_000)
        XCTAssertTrue(v.hasMeasuredPower, "the > 0 gate alone accepts 5,000 whp as a measurement")
        XCTAssertEqual(v.currentPowerFigure?.labeled, "5000 whp (measured)")
        let record = StewardGrounding.record(for: v)
        XCTAssertTrue(record.contains("5000 whp on the dyno") && record.contains("[Strong evidence]"),
                      "the LLM would be told 5,000 whp is a strong-evidence fact")
        // The entry-time validator is exactly what would have cautioned the owner first.
        XCTAssertNotNil(Vehicle.dynoAnomaly(proposingWheelHorsepower: 5_000))
    }

    func testRealisticDynoStillReadsAsMeasuredAndDrawsNoCaution() {
        let v = car(dyno: 477)
        XCTAssertEqual(v.currentPowerFigure?.labeled, "477 whp (measured)")
        XCTAssertNil(Vehicle.dynoAnomaly(proposingWheelHorsepower: 477), "a real dyno is never nagged")
    }
}
