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
