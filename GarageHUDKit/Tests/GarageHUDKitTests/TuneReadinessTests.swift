import XCTest
@testable import GarageHUDKit

final class TuneReadinessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_720_000_000)

    private var context: StewardContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return StewardContext(now: now, calendar: calendar)
    }

    private func preparedCar() -> Vehicle {
        var vehicle = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let installed = now.addingTimeInterval(-60 * 86_400)
        let dyno = now.addingTimeInterval(-20 * 86_400)
        vehicle.parts = [
            Part(name: "Supercharger", category: .forcedInduction, status: .installed, installDate: installed),
            Part(name: "Injectors", category: .fueling, status: .installed, installDate: installed),
            Part(name: "Radiator", category: .cooling, status: .installed, installDate: installed),
            Part(name: "Hondata ECU tune", category: .electronics, status: .installed, installDate: installed)
        ]
        vehicle.performanceRecords = [PerformanceRecord(date: dyno, type: .dyno, wheelHorsepower: 420)]
        vehicle.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6,
                                               lastServiced: now.addingTimeInterval(-30 * 86_400))]
        vehicle.operatingEnvelopeOverride = OperatingEnvelope(
            boostCautionPsi: 18,
            maxSustainedBoostPsi: 22,
            expectedBoostByRPM: [
                BoostBand(rpmLow: 3000, rpmHigh: 5000, expectedLowPsi: 10, expectedHighPsi: 16),
                BoostBand(rpmLow: 5001, rpmHigh: 7000, expectedLowPsi: 14, expectedHighPsi: 20)
            ])
        return vehicle
    }

    func testCoherentRecordedTuneIsReady() {
        let result = Steward.tuneReadiness(preparedCar(), context: context)
        XCTAssertEqual(result.state, .ready)
        XCTAssertEqual(result.holdCount, 0)
        XCTAssertEqual(result.verifyCount, 0)
    }

    func testCeilingBelowRequestedTargetHoldsPull() {
        var vehicle = preparedCar()
        vehicle.operatingEnvelopeOverride?.maxSustainedBoostPsi = 15
        let result = Steward.tuneReadiness(vehicle, context: context)
        XCTAssertEqual(result.state, .hold)
        XCTAssertEqual(result.checks.first { $0.id == "profile.ceiling" }?.state, .hold)
    }

    func testOverlappingBandsHoldPull() {
        var vehicle = preparedCar()
        vehicle.operatingEnvelopeOverride?.expectedBoostByRPM[1].rpmLow = 4500
        let result = Steward.tuneReadiness(vehicle, context: context)
        XCTAssertEqual(result.checks.first { $0.id == "profile.continuity" }?.state, .hold)
    }

    func testHardwareInstalledAfterDynoMakesValidationStale() {
        var vehicle = preparedCar()
        vehicle.parts.append(Part(name: "Larger pulley", category: .forcedInduction, status: .installed,
                                  installDate: now.addingTimeInterval(-2 * 86_400)))
        let result = Steward.tuneReadiness(vehicle, context: context)
        XCTAssertEqual(result.checks.first { $0.id == "validation.staleDyno" }?.state, .hold)
    }

    func testUndocumentedSupportRequestsVerificationWithoutClaimingItIsMissing() {
        var vehicle = preparedCar()
        vehicle.parts.removeAll { $0.category == .fueling }
        let result = Steward.tuneReadiness(vehicle, context: context)
        let fuel = result.checks.first { $0.id == "support.Fueling" }
        XCTAssertEqual(fuel?.state, .verify)
        XCTAssertTrue(fuel?.detail.localizedCaseInsensitiveContains("not documented") == true)
    }

    func testConfirmedStockFuelingHoldsBoostedPull() {
        var vehicle = preparedCar()
        vehicle.parts.removeAll { $0.category == .fueling }
        vehicle.confirmedStockSystems.insert(.fueling)
        let result = Steward.tuneReadiness(vehicle, context: context)
        XCTAssertEqual(result.checks.first { $0.id == "support.Fueling" }?.state, .hold)
    }

    func testNaturallyAspiratedCarDoesNotGetBoostSupportChecks() {
        var vehicle = Vehicle(make: "Honda", model: "Civic", year: 2020, garageSlot: 1)
        vehicle.parts = [Part(name: "ECU flash", category: .electronics, status: .installed)]
        let result = Steward.tuneReadiness(vehicle, context: context)
        XCTAssertFalse(result.checks.contains { $0.id == "support.Fueling" || $0.id == "support.Cooling" })
        XCTAssertEqual(result.checks.first { $0.id == "profile.na" }?.state, .ready)
    }

    func testMapSensorDoesNotMasqueradeAsCalibration() {
        var vehicle = Vehicle(make: "Honda", model: "Civic", year: 2020, garageSlot: 1)
        vehicle.parts = [Part(name: "4 bar MAP sensor", category: .electronics, status: .installed)]
        let result = Steward.tuneReadiness(vehicle, context: context)
        XCTAssertEqual(result.checks.first { $0.id == "calibration.missing" }?.state, .verify)
    }

    func testRecentMeasuredCeilingBreachOverridesOtherwiseReadySetup() {
        var vehicle = preparedCar()
        let end = now.addingTimeInterval(-60)
        vehicle.pullReports = [PullReport(
            startedAt: end.addingTimeInterval(-3), endedAt: end, feedLabel: "OBD-II Adapter",
            rpmStart: 3000, rpmPeak: 6500, rpmEnd: 6400,
            boostPeakPsi: 23, boostBreachedCeiling: true, boostCeilingPsi: 22,
            onTargetFraction: 0.4, overTargetFraction: 0.6, underTargetFraction: 0,
            coolantStartF: 190, coolantPeakF: 194, coolantDeltaF: 4,
            sampleCount: 20, measuredBoostFraction: 1, confidence: .confirmed)]

        let result = Steward.tuneReadiness(vehicle, context: context)

        XCTAssertEqual(result.state, .hold)
        XCTAssertEqual(result.checks.first { $0.id == "validation.pullHistory" }?.state, .hold)
    }
}
