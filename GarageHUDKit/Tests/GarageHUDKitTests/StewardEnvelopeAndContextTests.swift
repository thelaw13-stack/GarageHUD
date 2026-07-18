import XCTest
@testable import GarageHUDKit

/// Live reasoning must respect each car's own operating envelope — generic thresholds create
/// false alarms and false reassurance. And the reasoning must be a pure function of an
/// injected clock, not wall-time.
final class StewardEnvelopeAndContextTests: XCTestCase {

    private func boostedCar() -> Vehicle {
        var v = Vehicle(make: "T", model: "Turbo", year: 2020, garageSlot: 1)
        v.parts = [Part(name: "Turbo", category: .forcedInduction, status: .installed)]
        return v
    }

    private func naCar() -> Vehicle {
        var v = Vehicle(make: "T", model: "NA", year: 2020, garageSlot: 1)
        v.parts = [Part(name: "Header", category: .exhaust, status: .installed)]
        return v
    }

    private func boostFrame(psi: Double, throttle: Double) -> LiveTelemetryFrame {
        LiveTelemetryFrame(
            boostPsi: TimedMeasurement(psi, source: .obdAdapter),
            throttlePercent: TimedMeasurement(throttle, source: .obdAdapter),
            connectionState: .polling)
    }

    func testBoostIrrelevantOnNaturallyAspiratedCar() {
        // 20 psi is nonsense on an NA car — its envelope has no boost signal, so: silence.
        let obs = Steward.observe(frame: boostFrame(psi: 20, throttle: 100), for: naCar())
        XCTAssertTrue(obs.filter { $0.ruleID == "live.boost" }.isEmpty)
    }

    func testBoostOnlyFlaggedUnderThrottle() {
        // High boost value but closed throttle → likely noise/sensor, no claim.
        let coasting = Steward.observe(frame: boostFrame(psi: 20, throttle: 5), for: boostedCar())
        XCTAssertTrue(coasting.filter { $0.ruleID == "live.boost" }.isEmpty)
        // Same boost under throttle → a real observation.
        let pulling = Steward.observe(frame: boostFrame(psi: 20, throttle: 90), for: boostedCar())
        XCTAssertTrue(pulling.contains { $0.ruleID == "live.boost" })
    }

    private func frame(rpm: Double, boost: Double, throttle: Double) -> LiveTelemetryFrame {
        LiveTelemetryFrame(
            rpm: TimedMeasurement(rpm, source: .obdAdapter),
            boostPsi: TimedMeasurement(boost, source: .obdAdapter),
            throttlePercent: TimedMeasurement(throttle, source: .obdAdapter),
            connectionState: .polling)
    }

    private func tunedCar() -> Vehicle {
        var v = boostedCar()
        v.operatingEnvelopeOverride = OperatingEnvelope(
            boostCautionPsi: 18,
            maxSustainedBoostPsi: 22,
            expectedBoostByRPM: [
                BoostBand(rpmLow: 3000, rpmHigh: 5000, expectedLowPsi: 14, expectedHighPsi: 18),
                BoostBand(rpmLow: 5001, rpmHigh: 7000, expectedLowPsi: 16, expectedHighPsi: 20)
            ])
        return v
    }

    func testOverCeilingIsAdvisory() {
        let obs = Steward.observe(frame: frame(rpm: 6000, boost: 24, throttle: 100), for: tunedCar())
        let ceiling = obs.first { $0.ruleID == "live.boostCeiling" }
        XCTAssertNotNil(ceiling)
        XCTAssertEqual(ceiling?.tone, .advisory)
    }

    func testBoostAboveBandTargetIsCaution() {
        // 21 psi at 4000 rpm — band tops at 18, but under the 22 ceiling.
        let obs = Steward.observe(frame: frame(rpm: 4000, boost: 21, throttle: 100), for: tunedCar())
        XCTAssertTrue(obs.contains { $0.ruleID == "live.boostOverTarget" && $0.tone == .caution })
        XCTAssertFalse(obs.contains { $0.ruleID == "live.boostCeiling" })
    }

    func testBoostBelowBandTargetIsInformational() {
        let obs = Steward.observe(frame: frame(rpm: 4000, boost: 9, throttle: 100), for: tunedCar())
        XCTAssertTrue(obs.contains { $0.ruleID == "live.boostUnderTarget" && $0.tone == .informational })
    }

    func testTuneProfileSupersedesGenericBoostCaution() {
        // In-band and on target → no generic "live.boost" caution should fire.
        let obs = Steward.observe(frame: frame(rpm: 4000, boost: 16, throttle: 100), for: tunedCar())
        XCTAssertTrue(obs.filter { $0.ruleID.hasPrefix("live.boost") }.isEmpty)
    }

    func testCoolantUsesVehicleEnvelopeThresholds() {
        var v = boostedCar()
        v.operatingEnvelopeOverride = OperatingEnvelope(coolantCautionF: 200, coolantCriticalF: 220, boostCautionPsi: 18)
        let frame = LiveTelemetryFrame(coolantTempF: TimedMeasurement(225, source: .obdAdapter), connectionState: .polling)
        // 225 is below the default 235 but above this car's custom 220 → critical/advisory.
        XCTAssertTrue(Steward.observe(frame: frame, for: v).contains { $0.ruleID == "live.coolantCritical" })
    }

    func testFactoryPowerBasisIsCrankAndEfficiencyIsWheelNormalized() {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        XCTAssertEqual(v.factoryPowerBasis, .factoryCrank)
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 320)]
        v.documentedTotalInvestment = 12_000
        // The efficiency figure (a Specs/grounding statistic since W-046) stays wheel-normalized
        // and caveated at its home surface.
        let record = StewardGrounding.record(for: v)
        XCTAssertTrue(record.localizedCaseInsensitiveContains("per wheel-hp"))
        XCTAssertTrue(record.localizedCaseInsensitiveContains("not dyno-corrected"))
    }

    // MARK: Crank -> wheel normalization

    func testGainNormalizesCrankBaselineToWheel() {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.factoryHorsepower = 200           // crank
        v.drivetrain = .rwd                 // 15% typical loss → ~170 whp stock baseline
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 320)]
        XCTAssertEqual(v.estimatedStockWheelHP ?? 0, 170, accuracy: 0.001)
        XCTAssertEqual(v.horsepowerGainedOverStock ?? 0, 150, accuracy: 0.001)  // 320 - 170
        XCTAssertFalse(v.stockWheelBaselineIsAssumed)                            // drivetrain known
    }

    func testUnknownDrivetrainUsesAssumedLossAndFlagsIt() {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 320)]
        XCTAssertTrue(v.stockWheelBaselineIsAssumed)
        XCTAssertEqual(v.estimatedStockWheelHP ?? 0, 170, accuracy: 0.001)       // 15% assumed
    }

    func testWheelBasisFactoryNeedsNoNormalization() {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.factoryHorsepower = 180
        v.factoryPowerBasis = .measuredWheel   // already at the wheels
        v.drivetrain = .awd
        XCTAssertEqual(v.estimatedStockWheelHP ?? 0, 180, accuracy: 0.001)       // unchanged
        XCTAssertFalse(v.stockWheelBaselineIsAssumed)
    }

    func testNoGainWithoutAWheelDyno() {
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        v.factoryHorsepower = 200            // factory only, no wheel dyno
        XCTAssertNil(v.horsepowerGainedOverStock)
    }

    func testInjectedClockMakesFreshnessDeterministic() {
        // A fixed context: "quiet build" depends on context.now, not wall-clock.
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
        var v = Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1)
        let twoHundredDaysBefore = fixedNow.addingTimeInterval(-200 * 86_400)
        v.buildEvents = [BuildEvent(date: twoHundredDaysBefore, title: "last")]
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let ctx = StewardContext(now: fixedNow, calendar: utc)
        let first = Steward.observe(v, context: ctx).first { $0.ruleID == "build.quiet" }
        let second = Steward.observe(v, context: ctx).first { $0.ruleID == "build.quiet" }
        XCTAssertNotNil(first)
        XCTAssertTrue(first!.evidence.contains("200 days"))         // exact and stable under a fixed clock
        XCTAssertEqual(first!.evidence, second!.evidence)           // same input → same output
    }
}
