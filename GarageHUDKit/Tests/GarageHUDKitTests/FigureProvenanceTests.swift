import XCTest
@testable import GarageHUDKit

/// The tap-through evidence behind each headline figure — "never pretend certainty, always
/// explain" made concrete. Each provenance must state the figure's real source, disclose the
/// assumptions under it, and volunteer the caveats (stale hardware, self-disagreeing record)
/// rather than waiting to be caught.
final class FigureProvenanceTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Date(timeIntervalSinceNow: Double(offset) * 86_400) }

    // MARK: Power

    func testMeasuredPowerNamesTheDynoAndDisclosesStaleness() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.drivetrain = .rwd
        v.performanceRecords = [PerformanceRecord(date: day(-60), type: .dyno, wheelHorsepower: 477,
                                                  location: "Church Automotive")]
        v.parts = [Part(name: "Bigger injectors", category: .fueling, status: .installed, installDate: day(-10))]

        let p = ProvenanceBuilder.power(for: v)!
        XCTAssertEqual(p.headline, "477 whp (measured)")
        XCTAssertTrue(p.lines.contains { $0.contains("Measured 477 whp") && $0.contains("Church Automotive") })
        XCTAssertTrue(p.lines.contains { $0.contains("Bigger injectors") && $0.contains("after this dyno") },
                      "hardware changed after the measurement — the provenance must volunteer that")
        XCTAssertTrue(p.lines.contains { $0.contains("Factory rating: 237 hp") })
    }

    func testUnmeasuredPowerStatesTheEstimateAndItsAssumptions() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1, factoryHorsepower: 381)
        let p = ProvenanceBuilder.power(for: v)!
        XCTAssertEqual(p.headline, "381 hp (factory rated)")
        XCTAssertTrue(p.lines.contains { $0.contains("no measured dyno figure") })
        XCTAssertTrue(p.lines.contains { $0.contains("drivetrain unspecified") },
                      "an assumed driveline loss must say it's assumed")

        v.performanceRecords = [PerformanceRecord(type: .dyno)]   // numberless session
        let p2 = ProvenanceBuilder.power(for: v)!
        XCTAssertTrue(p2.lines.contains { $0.contains("carries no measured figure") },
                      "a logged numberless dyno is acknowledged, never denied")
    }

    // MARK: Investment

    func testInvestmentExplainsTheMaxRuleWithBothInputs() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.parts = [Part(name: "SC kit", category: .forcedInduction, status: .installed, cost: 5_000),
                   Part(name: "Turbo dreams", category: .engine, status: .wishlist, cost: 9_000)]
        v.documentedTotalInvestment = 25_000

        let p = ProvenanceBuilder.investment(for: v)!
        XCTAssertEqual(p.headline, "$25,000 documented")
        XCTAssertTrue(p.lines.contains { $0.contains("Itemized: $5,000 across 1 priced installed part") })
        XCTAssertTrue(p.lines.contains { $0.contains("Documented build-sheet total: $25,000") })
        XCTAssertTrue(p.lines.contains { $0.contains("documented total leads") })
        XCTAssertTrue(p.lines.contains { $0.contains("$9,000") && $0.contains("not included") },
                      "planned money is disclosed as excluded")
    }

    // MARK: Odometer

    func testOdometerNamesItsSourceEventAndLearnedRate() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [BuildEvent(date: day(-30), title: "Oil change", mileage: 50_000),
                         BuildEvent(date: day(0), title: "Fill-up", mileage: 51_500)]
        let p = ProvenanceBuilder.odometer(for: v)!
        XCTAssertEqual(p.headline, "51,500 mi (recorded)")
        XCTAssertTrue(p.lines.contains { $0.contains("Fill-up") })
        XCTAssertTrue(p.lines.contains { $0.contains("mi/day") && $0.contains("2 dated readings") })
    }

    func testOdometerDisclosesASelfDisagreeingRecord() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        v.buildEvents = [BuildEvent(date: day(-30), title: "Odometer", mileage: 58_000),
                         BuildEvent(date: day(0), title: "Odometer", mileage: 51_000)]
        let p = ProvenanceBuilder.odometer(for: v)!
        XCTAssertTrue(p.lines.contains { $0.contains("disagrees with itself") })
    }

    func testNoFigureMeansNoProvenance() {
        let bare = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1)
        XCTAssertNil(ProvenanceBuilder.power(for: bare))
        XCTAssertNil(ProvenanceBuilder.investment(for: bare))
        XCTAssertNil(ProvenanceBuilder.odometer(for: bare))
    }
}
