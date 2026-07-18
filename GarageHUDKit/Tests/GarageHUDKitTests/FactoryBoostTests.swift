import XCTest
@testable import GarageHUDKit

/// W-045 — factory-turbocharged awareness. A factory charger is part of the car, never a
/// modification: the app must reason about its boost (live limits, boost maps) without lying
/// that "forced induction is installed," and must leave a BONE-STOCK factory-turbo car out of
/// support scrutiny entirely — its fueling, cooling, and driveline were engineered for that
/// boost at the showroom. Scrutiny begins when the record shows the boost turned up.
final class FactoryBoostTests: XCTestCase {

    /// Tim's real Fozzy shape: factory-turbo Forester XT, Cobb + bolt-ons, 381 whp on E85.
    private func fozzy(tuned: Bool) -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1,
                        factoryHorsepower: 224, dateAdded: .now)
        v.engineDescription = "2.5L turbocharged flat-4"
        v.drivetrain = .awd
        if tuned {
            v.parts = [Part(name: "Cobb Accessport", category: .electronics, status: .installed),
                       Part(name: "Downpipe", category: .exhaust, status: .installed)]
            v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 381)]
        } else {
            v.parts = [Part(name: "All-weather mats", category: .interior, status: .installed)]
        }
        return v
    }

    // MARK: Inference & override

    func testInfersFactoryBoostFromEngineDescriptionAndModelMarkers() {
        XCTAssertTrue(fozzy(tuned: false).hasFactoryForcedInduction, "engine says 'turbocharged'")

        var wrx = Vehicle(make: "Subaru", model: "WRX", year: 2020, garageSlot: 1)
        XCTAssertTrue(wrx.hasFactoryForcedInduction, "WRX is a known factory-boosted marker")

        let miata = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1)
        XCTAssertFalse(miata.hasFactoryForcedInduction, "an NA car stays NA")

        wrx.factoryForcedInductionOverride = false
        XCTAssertFalse(wrx.hasFactoryForcedInduction, "the owner's override wins either way")
    }

    // MARK: The two gates

    func testStockFactoryTurboStaysOutOfSupportScrutiny() {
        let stock = fozzy(tuned: false)
        XCTAssertTrue(stock.runsBoost, "it makes boost — live limits and maps apply")
        XCTAssertFalse(stock.runsElevatedBoost, "but the factory engineered this support")
        XCTAssertNil(Steward.assess(stock), "nothing to assess on a stock car")
        XCTAssertFalse(Steward.observe(stock).contains { StewardRuleID.isGap($0.ruleID) },
                       "no fueling/cooling gap nags on a showroom-stock turbo car")
    }

    func testTunedFactoryTurboEarnsSupportScrutinyWithHonestWording() {
        let tuned = fozzy(tuned: true)
        XCTAssertTrue(tuned.runsElevatedBoost, "a tune on record turns scrutiny on")

        let gaps = Steward.observe(tuned).filter { StewardRuleID.isGap($0.ruleID) }
        XCTAssertFalse(gaps.isEmpty, "fueling/cooling now answer for the turned-up boost")
        for gap in gaps {
            XCTAssertFalse(gap.evidence.contains("Forced induction is installed"),
                           "a factory charger is never called an install: \(gap.evidence)")
            XCTAssertTrue(gap.evidence.contains("running a tune"), gap.evidence)
        }
        XCTAssertNotNil(Steward.assess(tuned), "a tuned factory-turbo build gets an assessment")
    }

    func testBigMeasuredGainAloneAlsoTurnsScrutinyOn() {
        var gained = fozzy(tuned: false)
        // No calibration logged, but a dyno well past the ~179 whp stock baseline.
        gained.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 381)]
        XCTAssertTrue(gained.runsElevatedBoost)
        let gap = Steward.observe(gained).first { StewardRuleID.isGap($0.ruleID) }
        XCTAssertTrue(gap?.evidence.contains("well over its stock power") == true,
                      "the gain path states the gain, not a phantom tune")
    }

    // MARK: Live envelope & tuner

    func testFactoryTurboGetsALiveBoostEnvelopeByDefault() {
        XCTAssertNotNil(fozzy(tuned: false).operatingEnvelope.boostCautionPsi,
                        "boost is a meaningful live signal on any turbo car")
        let miata = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1)
        XCTAssertNil(miata.operatingEnvelope.boostCautionPsi)
    }

    func testBoostMapOnAFactoryTurboIsLegitimateNotAHold() {
        var v = fozzy(tuned: false)
        v.operatingEnvelopeOverride = OperatingEnvelope(boostCautionPsi: 16, maxSustainedBoostPsi: 18)
        let readiness = Steward.tuneReadiness(v)
        XCTAssertFalse(readiness.checks.contains { $0.id == "profile.unexpectedBoost" },
                       "a factory-turbo car with boost targets is normal, not a conflict")
    }

    func testCobbCountsAsTheCalibrationRecord() {
        let tuned = fozzy(tuned: true)
        XCTAssertEqual(tuned.calibrationPartOnRecord?.name, "Cobb Accessport")
        XCTAssertTrue(Steward.tuneReadiness(tuned).checks
            .contains { $0.id == "calibration.recorded" })
    }
}
