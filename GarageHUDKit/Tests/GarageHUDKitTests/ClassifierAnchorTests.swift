import XCTest
@testable import GarageHUDKit

/// W-053 — Fable fix #2: "calibrating values while guessing classifiers just relocates the
/// guess." These pin the exact misroutes the re-review proved by construction, plus the two
/// doors that now open: the owner's OBD-II override, and the flagged-pull acknowledgment.
final class ClassifierAnchorTests: XCTestCase {

    // MARK: The two proven misroutes, permanently dead

    func testSubaruBajaTurboIsNotAnAircooledVW() {
        var v = Vehicle(make: "Subaru", model: "Baja", year: 2005, trim: "Turbo", garageSlot: 1,
                        factoryHorsepower: 210)
        v.engineDescription = "2.5L turbocharged flat-4"
        XCTAssertNil(v.platformBaseline, "no make-anchored entry matches; falls to safe defaults")
        XCTAssertFalse(v.isAirCooled)
        XCTAssertTrue(v.supportsOBD2, "a 2005 US truck has a port")
        XCTAssertNotNil(v.operatingEnvelope.coolantCautionF,
                        "coolant warnings NEVER silently suppressed on a liquid-cooled car")
    }

    func testModernBeetleIsNotAType1() {
        var v = Vehicle(make: "Volkswagen", model: "Beetle", year: 2019, garageSlot: 1,
                        factoryHorsepower: 174)
        v.engineDescription = "2.0L TSI turbocharged inline-4"
        XCTAssertNil(v.platformBaseline, "Type 1 entry is year-capped at 2003")
        XCTAssertFalse(v.isAirCooled)
        XCTAssertTrue(v.supportsOBD2)
    }

    // MARK: The cars that SHOULD match still do

    func testTimsAircooledBajaStillMatches() {
        var v = Vehicle(make: "Volkswagen", model: "Baja Bug", year: 1971, garageSlot: 1)
        v.engineDescription = "1.6L air-cooled flat-4"
        XCTAssertEqual(v.platformBaseline?.id, "vw-aircooled-type1")
        XCTAssertTrue(v.isAirCooled)
        XCTAssertFalse(v.supportsOBD2)
        XCTAssertNil(v.operatingEnvelope.coolantCautionF, "no coolant limit on a car with no coolant")
    }

    func testFozzyStillMatchesTheEJEntry() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.engineDescription = "2.5L turbocharged flat-4"
        XCTAssertEqual(v.platformBaseline?.id, "subaru-ej-turbo")
    }

    /// The owner's own engine text outranks the catalog: an air-cooled Porsche isn't in the
    /// catalog (and must not be attributed to the VW entry), but "air-cooled" in the owner's
    /// description is honored.
    func testAircooledPorscheHonoredWithoutVWAttribution() {
        var v = Vehicle(make: "Porsche", model: "911 Carrera", year: 1987, garageSlot: 1)
        v.engineDescription = "3.2L air-cooled flat-six"
        XCTAssertNil(v.platformBaseline, "no cross-make attribution — VW sources never cited for a Porsche")
        XCTAssertTrue(v.isAirCooled, "the owner's words about their engine are honored")
    }

    // MARK: The OBD-II override

    func testOwnerOverrideBeatsTheYearRuleBothWays() {
        var swapped = Vehicle(make: "Volkswagen", model: "Baja Bug", year: 1971, garageSlot: 1)
        swapped.engineDescription = "EJ255 swap, standalone ECU with OBD-II gateway"
        XCTAssertFalse(swapped.supportsOBD2, "heuristic says no…")
        swapped.obd2Override = true
        XCTAssertTrue(swapped.supportsOBD2, "…the owner says yes, and wins")

        var import98 = Vehicle(make: "Nissan", model: "Skyline GT-R", year: 1998, garageSlot: 2)
        XCTAssertTrue(import98.supportsOBD2, "year rule promises a port…")
        import98.obd2Override = false
        XCTAssertFalse(import98.supportsOBD2, "…the owner knows their import, and wins")
    }

    // MARK: The flagged-pull door now opens

    private func flaggedPullCar() -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1,
                        factoryHorsepower: 224)
        v.engineDescription = "2.5L turbocharged flat-4"
        v.pullReports = [PullReport(
            startedAt: Date(timeIntervalSinceNow: -40 * 86_400),
            endedAt: Date(timeIntervalSinceNow: -40 * 86_400 + 8),
            feedLabel: "OBD-II Adapter", rpmStart: 2500, rpmPeak: 6200, rpmEnd: 6100,
            boostPeakPsi: 21.4, boostBreachedCeiling: true, boostCeilingPsi: 18,
            onTargetFraction: 0.4, overTargetFraction: 0.6, underTargetFraction: 0.0,
            coolantStartF: 190, coolantPeakF: 208, coolantDeltaF: 18,
            sampleCount: 160, measuredBoostFraction: 1.0, confidence: .strong)]
        return v
    }

    func testAcknowledgeIsOfferedFirstAndActuallyClearsTheFlag() {
        var v = flaggedPullCar()
        let obs = Steward.observe(v).first { StewardRuleID.isPullFlagged($0.ruleID) }
        XCTAssertNotNil(obs, "an unresolved breach stays actionable — no clock")

        // The first offered door is the acknowledgment, and its verb parses to the right report.
        let options = StewardResolution.options(for: obs!, in: v)
        guard case .acknowledgePull(let id)? = options.first?.action else {
            return XCTFail("acknowledge must be the first door: \(options.map(\.title))")
        }
        XCTAssertEqual(id, v.pullReports[0].id)

        // Doing the offered thing CLEARS the observation (the W-042 effectiveness contract)…
        XCTAssertTrue(v.acknowledgePullReport(id))
        XCTAssertFalse(Steward.observe(v).contains { StewardRuleID.isPullFlagged($0.ruleID) })
        // …and the resolution is itself a record, not a dismissal.
        XCTAssertTrue(v.buildEvents.contains { $0.title.hasPrefix("Pull flag acknowledged") })
        XCTAssertFalse(v.acknowledgePullReport(id), "acknowledging twice is a no-op, not a new event")
    }

    func testLaterCleanPullStillClearsWithoutAcknowledgment() {
        var v = flaggedPullCar()
        v.pullReports.append(PullReport(
            startedAt: .now, endedAt: .now, feedLabel: "OBD-II Adapter",
            rpmStart: 2500, rpmPeak: 6200, rpmEnd: 6000, boostPeakPsi: 16,
            boostBreachedCeiling: false, boostCeilingPsi: 22,
            onTargetFraction: 0.9, overTargetFraction: 0.05, underTargetFraction: 0.05,
            coolantStartF: 190, coolantPeakF: 200, coolantDeltaF: 10,
            sampleCount: 150, measuredBoostFraction: 1.0, confidence: .strong))
        XCTAssertFalse(Steward.observe(v).contains { StewardRuleID.isPullFlagged($0.ruleID) })
    }
}
