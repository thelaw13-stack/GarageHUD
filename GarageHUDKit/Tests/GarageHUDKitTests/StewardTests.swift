import XCTest
@testable import GarageHUDKit

/// Steward is the reasoning core; its rules and confidence-bearing output are pinned so
/// the app never silently starts advising differently than the Constitution intends.
final class StewardTests: XCTestCase {
    private func vehicle(_ parts: [Part] = []) -> Vehicle {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = parts
        return v
    }

    func testForcedInductionWithoutFuelingIsObserved() {
        let obs = Steward.observe(vehicle([Part(name: "Turbo", category: .forcedInduction, status: .installed)]))
        XCTAssertTrue(obs.contains { $0.statement.localizedCaseInsensitiveContains("fueling") })
        // Every observation must carry a real confidence and evidence — no bare claims.
        XCTAssertTrue(obs.allSatisfy { (1...100).contains($0.confidence) && !$0.evidence.isEmpty })
    }

    func testSupportedForcedInductionSuppressesGapObservations() {
        let obs = Steward.observe(vehicle([
            Part(name: "Turbo", category: .forcedInduction, status: .installed),
            Part(name: "Pump", category: .fueling, status: .installed),
            Part(name: "Radiator", category: .cooling, status: .installed),
            Part(name: "BBK", category: .brakes, status: .installed)
        ]))
        XCTAssertFalse(obs.contains { $0.statement.localizedCaseInsensitiveContains("fueling") })
        XCTAssertFalse(obs.contains { $0.statement.localizedCaseInsensitiveContains("heat") })
    }

    func testCostEfficiencyIsHighConfidenceDerivedFact() {
        var v = vehicle()
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 350)]
        v.documentedTotalInvestment = 15_000

        let cost = Steward.observe(v).first { $0.statement.localizedCaseInsensitiveContains("cost-to-power") }
        XCTAssertNotNil(cost)
        XCTAssertGreaterThanOrEqual(cost!.confidence, 90)
        XCTAssertEqual(cost!.provenance, .derived)
    }

    func testQuietBuildProducesFreshnessObservation() {
        var v = vehicle()
        let old = Calendar.current.date(byAdding: .day, value: -200, to: .now)!
        v.performanceRecords = [PerformanceRecord(date: old, type: .dyno, wheelHorsepower: 300)]
        XCTAssertTrue(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("quiet") })
    }

    func testLiveHighCoolantIsAdvisoryAndEstimated() {
        let metrics = LiveMetrics(rpm: 6000, speedMph: 80, coolantTempF: 240, boostPsi: 12, throttlePercent: 100)
        let obs = Steward.observe(live: metrics, for: vehicle())
        XCTAssertTrue(obs.contains { $0.tone == .advisory && $0.provenance == .estimatedLive })
    }

    func testObservationsOrderAdvisoryAboveInformational() {
        var v = vehicle([Part(name: "Turbo", category: .forcedInduction, status: .installed)]) // caution
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 350)] // informational cost fact
        v.documentedTotalInvestment = 15_000
        let obs = Steward.observe(v)
        guard let firstInfoIndex = obs.firstIndex(where: { $0.tone == .informational }),
              let firstCautionIndex = obs.firstIndex(where: { $0.tone == .caution }) else {
            return XCTFail("expected both a caution and an informational observation")
        }
        XCTAssertLessThan(firstCautionIndex, firstInfoIndex, "cautions should rank above informational facts")
    }
}
