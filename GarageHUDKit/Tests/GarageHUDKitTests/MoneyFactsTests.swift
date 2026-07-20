import XCTest
@testable import GarageHUDKit

/// W-072 — the three money facts stay distinct, at entry and in every total.
///
/// The Baja's $8,000 acquisition cost was entered into the build slot and every surface faithfully
/// reported it *as build spend*. The app was not wrong; the entry didn't name the roles as a set.
/// These pin both the distinctness of the totals and the single-source-of-truth labels the entry
/// screen now reads from.
final class MoneyFactsTests: XCTestCase {

    private func car() -> Vehicle {
        Vehicle(make: "VW", model: "Beetle Baja", year: 1970, garageSlot: 1)
    }

    func testAcquisitionCostNeverLeaksIntoTheBuildTotal() {
        // The core W-072 invariant: what you paid to buy the car is not build investment.
        var v = car()
        v.purchasePrice = 8_000
        XCTAssertNil(v.amount(of: .build), "purchase price must not appear as build spend")
        XCTAssertEqual(v.amount(of: .acquisition), 8_000)
        XCTAssertEqual(v.totalInvested, 0, "totalInvested must exclude the purchase price")
    }

    func testTheThreeFactsAreReadFromSeparateStores() {
        var v = car()
        v.purchasePrice = 8_000
        v.documentedTotalInvestment = 14_000
        // service spend is derived from records; none here → nil
        XCTAssertEqual(v.amount(of: .acquisition), 8_000)
        XCTAssertEqual(v.amount(of: .build), 14_000)
        XCTAssertNil(v.amount(of: .service))
        // And they are never summed into one another.
        XCTAssertNotEqual(v.amount(of: .build), (v.purchasePrice ?? 0) + 14_000)
    }

    func testEveryFactNamesWhatItIsNot() {
        // The guard at entry is the "not …" clause; it must exist for each.
        XCTAssertTrue(MoneyFact.acquisition.distinctNote.lowercased().contains("not build"))
        XCTAssertTrue(MoneyFact.build.distinctNote.lowercased().contains("not the purchase"))
        XCTAssertTrue(MoneyFact.service.distinctNote.lowercased().contains("separate"))
    }

    func testRolesAreDistinctLabels() {
        let roles = Set(MoneyFact.allCases.map(\.role))
        XCTAssertEqual(roles.count, MoneyFact.allCases.count, "each fact needs its own label")
    }

    func testUnrecordedFactsReadAsNilNotZero() {
        // Constitution: unknown is not zero. An empty money fact is absent, not $0.
        let v = car()
        XCTAssertNil(v.amount(of: .acquisition))
        XCTAssertNil(v.amount(of: .build))
        XCTAssertNil(v.amount(of: .service))
    }
}
