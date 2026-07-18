import XCTest
@testable import GarageHUDKit

/// Rule ids are load-bearing: resolution buttons route by parsing them. Emitters and parsers
/// share `StewardRuleID`, and these round-trips make any format drift fail loudly instead of
/// silently killing a "Mark serviced" or "Confirm stock" button.
final class StewardRuleIDTests: XCTestCase {

    func testGapIDsRoundTripForEveryCategory() {
        for category in PartCategory.allCases {
            XCTAssertEqual(StewardRuleID.gapCategory(from: StewardRuleID.gap(category)), category,
                           "gap id must round-trip for \(category.rawValue)")
        }
        XCTAssertNil(StewardRuleID.gapCategory(from: "tune.stale"))
    }

    func testMaintenanceIDsRoundTrip() {
        let item = UUID()
        XCTAssertEqual(StewardRuleID.maintenanceItemID(from: StewardRuleID.maintenanceOverdue(item)), item)
        XCTAssertEqual(StewardRuleID.maintenanceItemID(from: StewardRuleID.maintenanceDueSoon(item)), item)
        XCTAssertTrue(StewardRuleID.isMaintenanceOverdue(StewardRuleID.maintenanceOverdue(item)))
        XCTAssertTrue(StewardRuleID.isMaintenanceDueSoon(StewardRuleID.maintenanceDueSoon(item)))
    }

    /// A NextStep that names an action must be actionable: it carries its source observation,
    /// and that observation resolves to concrete options (the tappable NEXT line's contract).
    func testNextStepCarriesAResolvableSource() {
        // Overdue maintenance → advisory next step → "Mark serviced" in place.
        var truck = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let oil = MaintenanceItem(name: "Oil change", intervalMonths: 6,
                                  lastServiced: Date(timeIntervalSinceNow: -300 * 86_400))
        truck.maintenance = [oil]
        let step = Steward.nextStep(truck)
        XCTAssertNotNil(step?.source, "an observation-driven step must carry its source")
        XCTAssertTrue(StewardResolution.options(for: step!.source!, in: truck)
            .contains { $0.action == .markServiced(oil.id) })

        // Assessment-driven step (undocumented fueling on a boosted car) → the matching gap
        // observation rides along, so the step resolves to confirm-stock / add-part.
        var s2k = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1)
        s2k.parts = [Part(name: "SC kit", category: .forcedInduction, status: .installed)]
        let gapStep = Steward.nextStep(s2k)
        XCTAssertNotNil(gapStep?.source, "the gap observation must ride along with the assessment step")
        XCTAssertTrue(StewardResolution.isActionable(gapStep!.source!, in: s2k))
    }

    /// "Address clutch/drivetrain" must carry its door even though observe() emits no gap rule
    /// for drivetrain — the step synthesizes one, so the verbs (confirm stock / add the part)
    /// can be offered in place. An instruction without a door was Tim's Fozzy report.
    func testAssessmentStepForNonGapCategoryStillCarriesItsVerbs() {
        var fozzy = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1,
                            factoryHorsepower: 224)
        fozzy.drivetrain = .awd
        fozzy.parts = [Part(name: "Big turbo", category: .forcedInduction, status: .installed),
                       Part(name: "Injectors", category: .fueling, status: .installed),
                       Part(name: "FMIC", category: .cooling, status: .installed),
                       Part(name: "Forged pistons", category: .engine, status: .installed)]
        // Past the owner's 450-whp driveline-attention line (W-044) — clutch is in scope.
        fozzy.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 480)]

        let step = Steward.nextStep(fozzy)
        XCTAssertNotNil(step, "an undocumented clutch/drivetrain at this power is a step")
        XCTAssertTrue(step!.action.localizedCaseInsensitiveContains("clutch"), step!.action)
        XCTAssertNotNil(step!.source, "the step must carry a synthesized gap observation")
        let actions = StewardResolution.options(for: step!.source!, in: fozzy).map(\.action)
        XCTAssertTrue(actions.contains(.confirmStock(.drivetrain)), "confirm-stock verb present")
        XCTAssertTrue(actions.contains(.addPart(.drivetrain)), "add-part verb present")
    }

    /// The teardown step must NOT carry a source: its only in-place resolution would be "mark
    /// back in service" — the opposite of "finish the teardown" (the W-039 trap). Its surface
    /// is the rebuild checklist.
    func testTeardownStepOffersNoContradictingVerbs() {
        var s2k = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1)
        s2k.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown")
        let step = Steward.nextStep(s2k)
        XCTAssertNotNil(step)
        XCTAssertNil(step!.source, "no verbs that contradict the step's own words")
    }

    /// End-to-end: an emitted observation must reach its intended resolution options.
    func testEmittedObservationsRouteToTheirResolutions() {
        // A mileage-overdue item → Mark serviced targeting exactly that item.
        var truck = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let oil = MaintenanceItem(name: "Oil change", intervalMonths: 12,
                                  lastServiced: Date(timeIntervalSinceNow: -30 * 86_400),
                                  intervalMiles: 5_000, lastServicedMileage: 50_000)
        truck.maintenance = [oil]
        truck.buildEvents = [BuildEvent(title: "Odo", mileage: 58_000)]
        let overdue = Steward.observe(truck).first { StewardRuleID.isMaintenanceOverdue($0.ruleID) }
        XCTAssertNotNil(overdue)
        XCTAssertTrue(StewardResolution.options(for: overdue!, in: truck)
            .contains { $0.action == .markServiced(oil.id) })

        // A fueling gap → Confirm-stock / Add-part for exactly that category.
        var s2k = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1)
        s2k.parts = [Part(name: "SC kit", category: .forcedInduction, status: .installed)]
        let gap = Steward.observe(s2k).first { StewardRuleID.isGap($0.ruleID) }
        XCTAssertNotNil(gap)
        let actions = StewardResolution.options(for: gap!, in: s2k).map(\.action)
        XCTAssertTrue(actions.contains(.confirmStock(.fueling)) || actions.contains(.confirmStock(.cooling)))
    }
}
