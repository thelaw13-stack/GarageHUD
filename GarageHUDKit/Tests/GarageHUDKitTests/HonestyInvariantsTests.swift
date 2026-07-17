import XCTest
@testable import GarageHUDKit

/// Honesty is the whole pitch: the app must never state an unmeasured number as measured, never
/// present a crank figure as a wheel one, and never count planned or asserted-away things as facts.
/// These grew out of an adversarial audit — each one is an attack that must keep failing.
final class HonestyInvariantsTests: XCTestCase {

    /// A dyno logged with NO value is not a measurement. It must not dress the factory (crank) figure
    /// up as "measured whp", nor shadow an earlier real dyno. (This was a live leak on the build sheet
    /// and fleet sheet — both shareable — until gated on `hasMeasuredPower`.)
    func testNumberlessDynoIsNeverLabeledMeasured() {
        var v = Vehicle(make: "Mazda", model: "MX-5", year: 2016, garageSlot: 1, factoryHorsepower: 155)
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: nil)]

        XCTAssertFalse(v.hasMeasuredPower, "a dyno with no number is not a measurement")
        XCTAssertNil(v.measuredWheelHorsepower)

        let sheet = BuildSheetExporter.text(for: v)
        XCTAssertTrue(sheet.contains("155 hp (factory rated)"), sheet)
        XCTAssertFalse(sheet.localizedCaseInsensitiveContains("155 whp"), "must not claim a measured wheel figure")
        XCTAssertFalse(sheet.localizedCaseInsensitiveContains("measured"), sheet)
    }

    /// A real earlier dyno must not be hidden by a later numberless one.
    func testEarlierRealDynoIsNotShadowedByALaterNumberlessOne() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.performanceRecords = [
            PerformanceRecord(date: .init(timeIntervalSince1970: 1_000), type: .dyno, wheelHorsepower: 300),
            PerformanceRecord(date: .init(timeIntervalSince1970: 2_000), type: .dyno, wheelHorsepower: nil),
        ]
        XCTAssertTrue(v.hasMeasuredPower)
        XCTAssertEqual(v.measuredWheelHorsepower, 300)
        XCTAssertEqual(v.currentHorsepowerEstimate, 300)   // the real 300, not the 237 crank fallback
    }

    /// A physically installed part outranks an owner's stale "confirmed stock" claim — the app resolves
    /// the contradiction toward the hardware that's actually there, rather than holding both.
    func testInstalledPartOverridesConfirmedStock() {
        var v = Vehicle(make: "Subaru", model: "WRX", year: 2015, garageSlot: 1, factoryHorsepower: 268)
        v.confirmedStockSystems = [.fueling]
        v.parts = [Part(name: "Injectors", category: .fueling, status: .installed)]
        XCTAssertEqual(v.knowledge(of: .fueling), .confirmedPresent)
    }

    /// The build assessment's power summary must never dress a factory crank rating up as "whp" —
    /// the third sighting of this bug class (after W-004 and W-021), caught by the Fable review in
    /// `BuildAssessment.powerSummary` and propagating into NextStep rationales and the dashboard.
    func testAssessmentPowerSummaryNeverLabelsCrankAsWheel() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1, factoryHorsepower: 240)
        v.parts = [Part(name: "Supercharger kit", category: .forcedInduction, status: .installed)]
        // No dyno anywhere on the record.
        let a = Steward.assess(v)!
        XCTAssertFalse(a.powerSummary.localizedCaseInsensitiveContains("whp"), a.powerSummary)
        XCTAssertTrue(a.powerSummary.contains("factory rated"), a.powerSummary)
        let step = Steward.nextStep(v)!
        XCTAssertFalse(step.rationale.localizedCaseInsensitiveContains("whp"), step.rationale)

        // And with a real dyno, "whp measured" is earned.
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 477)]
        XCTAssertTrue(Steward.assess(v)!.powerSummary.contains("477 whp"))
    }

    /// Wishlist money is planned, not spent. Spend-by-system (Specs and the LLM grounding) must
    /// only count installed parts — a $5,000 planned turbo must never appear as spend alongside a
    /// $100 total, handing the LLM a self-contradictory record.
    func testPlannedMoneyNeverReportedAsSpend() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1)
        v.parts = [
            Part(name: "Intake", category: .engine, status: .installed, cost: 100),
            Part(name: "Garrett turbo kit", category: .forcedInduction, status: .wishlist, cost: 5_000),
        ]
        XCTAssertEqual(v.spendByCategory.count, 1)
        XCTAssertEqual(v.spendByCategory.first?.category, .engine)
        let record = StewardGrounding.record(for: v)
        XCTAssertFalse(record.contains("Forced Induction ($5,000"), record)
        XCTAssertTrue(record.contains("$5,000.00 planned"), "planned spend still surfaces, as planned")
    }

    /// A mileage-overdue item must produce a Steward observation — the observation engine judges
    /// due-ness the same mileage-aware way as the briefing header, build sheet, and fleet health.
    /// (It once used the time-only overload: the header said "3,000 mi overdue" while the voice
    /// Steward said "Nothing stands out right now." — two surfaces contradicting each other.)
    func testMileageOverdueProducesAnObservation() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.maintenance = [MaintenanceItem(name: "Oil change", intervalMonths: 12,
                                         lastServiced: Date(timeIntervalSinceNow: -30 * 86_400),
                                         intervalMiles: 5_000, lastServicedMileage: 50_000)]
        v.buildEvents = [BuildEvent(title: "Odometer check", mileage: 58_000)]
        let obs = Steward.observe(v)
        let overdue = obs.first { $0.ruleID.hasPrefix("maintenance.overdue") }
        XCTAssertNotNil(overdue, "mileage-overdue must be observed, not just time-overdue")
        XCTAssertTrue(overdue!.evidence.contains("3,000 mi past the 55,000 mi mark"), overdue!.evidence)
        // The voice Steward now has something to say instead of "Nothing stands out".
        let reply = StewardConversation.reply(to: "what should I watch", vehicle: v)
        XCTAssertFalse(reply.text.contains("Nothing stands out"), reply.text)
    }

    /// A support-gap observation must never deny a logged part. With a wishlist part in the gap
    /// category, the evidence acknowledges the plan while the gap stays open.
    func testGapEvidenceAcknowledgesWishlistPart() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1)
        v.parts = [
            Part(name: "Supercharger kit", category: .forcedInduction, status: .installed),
            Part(name: "Walbro 255 fuel pump", category: .fueling, status: .wishlist, cost: 140),
        ]
        let gap = Steward.observe(v).first { $0.ruleID.lowercased() == "gap.fueling" }
        XCTAssertNotNil(gap)
        XCTAssertFalse(gap!.evidence.contains("No fuel system parts are logged"), gap!.evidence)
        XCTAssertTrue(gap!.statement.localizedCaseInsensitiveContains("planned but not yet installed"), gap!.statement)
    }

    /// The grounding record must not claim "no dyno logged" when a (numberless) dyno session is
    /// on the record the owner can see — that's a false statement about the record itself.
    func testGroundingAcknowledgesNumberlessDynoSession() {
        var v = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1, factoryHorsepower: 140)
        v.parts = [Part(name: "Exhaust", category: .exhaust, status: .installed)]
        v.performanceRecords = [PerformanceRecord(type: .dyno)]   // logged, no figure
        let record = StewardGrounding.record(for: v)
        XCTAssertFalse(record.contains("no dyno logged"), record)
        XCTAssertTrue(record.contains("carries no measured figure"), record)
    }

    /// A physically impossible dyno figure (zero or negative) is not a measurement and must never
    /// earn the "measured" label on a shareable document.
    func testNonPositiveDynoIsNotAMeasurement() {
        var v = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1, factoryHorsepower: 140)
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: -50)]
        XCTAssertFalse(v.hasMeasuredPower)
        let sheet = BuildSheetExporter.text(for: v)
        XCTAssertFalse(sheet.localizedCaseInsensitiveContains("measured)"), sheet)
        XCTAssertTrue(sheet.contains("140 hp (factory rated)"), sheet)
    }

    /// A planned (wishlist) part is intent, not a fact. It must never read as a supported/covered
    /// system — only as an open item with a plan against it.
    func testPlannedPartIsNotCountedAsCovered() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1, factoryHorsepower: 224)
        v.parts = [
            Part(name: "Big turbo", category: .forcedInduction, status: .installed),
            Part(name: "Injectors", category: .fueling, status: .wishlist),
        ]
        let fueling = Steward.assess(v)?.subsystems.first { $0.label.localizedCaseInsensitiveContains("fuel") }
        XCTAssertNotEqual(fueling?.status, .supported, "a planned part is not coverage")
    }
}
