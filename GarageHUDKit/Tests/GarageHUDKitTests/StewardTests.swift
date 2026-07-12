import XCTest
@testable import GarageHUDKit

/// Steward is the reasoning core; its rules and evidence-graded output are pinned so the app
/// never silently starts advising differently than the Constitution intends — and, crucially,
/// never conflates "not logged" with "not installed".
final class StewardTests: XCTestCase {
    private func vehicle(_ parts: [Part] = []) -> Vehicle {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = parts
        return v
    }

    /// A sparse record with forced induction and no fueling logged must be reported as
    /// *undocumented* (weak, informational) — never as a confirmed missing system.
    func testUndocumentedFuelingIsWeakAndNotAbsenceClaim() {
        let obs = Steward.observe(vehicle([Part(name: "Turbo", category: .forcedInduction, status: .installed)]))
        let fuel = obs.first { $0.ruleID == "gap.Fueling" }
        XCTAssertNotNil(fuel)
        XCTAssertEqual(fuel?.confidence, .weak)
        XCTAssertEqual(fuel?.tone, .informational)
        XCTAssertTrue(fuel!.statement.localizedCaseInsensitiveContains("hasn't been documented"))
        XCTAssertFalse(fuel!.statement.localizedCaseInsensitiveContains("missing"))
        XCTAssertTrue(obs.allSatisfy { !$0.evidence.isEmpty })
    }

    /// The same physical situation, but the owner confirmed the factory system remains, is a
    /// real, strong gap — the only case that earns a firm caution.
    func testConfirmedStockFuelingIsStrongCaution() {
        var v = vehicle([Part(name: "Turbo", category: .forcedInduction, status: .installed)])
        v.confirmedStockSystems = [.fueling]
        let fuel = Steward.observe(v).first { $0.ruleID == "gap.Fueling" }
        XCTAssertEqual(fuel?.confidence, .strong)
        XCTAssertEqual(fuel?.tone, .caution)
        XCTAssertTrue(fuel!.statement.localizedCaseInsensitiveContains("factory system is confirmed"))
    }

    /// The review's specific danger: a freshly created / barely-imported record must not be
    /// warned at, because we know nothing (`.unknown`), not that systems are absent.
    func testEmptyRecordProducesNoGapWarnings() {
        let obs = Steward.observe(vehicle())
        XCTAssertTrue(obs.filter { $0.ruleID.hasPrefix("gap.") }.isEmpty)
    }

    func testSupportedForcedInductionSuppressesGapObservations() {
        let obs = Steward.observe(vehicle([
            Part(name: "Turbo", category: .forcedInduction, status: .installed),
            Part(name: "Pump", category: .fueling, status: .installed),
            Part(name: "Radiator", category: .cooling, status: .installed),
            Part(name: "BBK", category: .brakes, status: .installed)
        ]))
        XCTAssertTrue(obs.filter { $0.ruleID.hasPrefix("gap.") }.isEmpty)
    }

    func testCostEfficiencyIsApproximateModerateFact() {
        var v = vehicle()
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 350)]
        v.documentedTotalInvestment = 15_000

        let cost = Steward.observe(v).first { $0.ruleID == "efficiency.costPerHp" }
        XCTAssertNotNil(cost)
        XCTAssertEqual(cost!.confidence, .moderate)         // approximate, not 97%
        XCTAssertTrue(cost!.evidence.localizedCaseInsensitiveContains("factory crank"))
        XCTAssertEqual(cost!.provenance, .derived)
    }

    func testQuietBuildProducesFreshnessObservation() {
        var v = vehicle()
        let old = Calendar.current.date(byAdding: .day, value: -200, to: .now)!
        v.performanceRecords = [PerformanceRecord(date: old, type: .dyno, wheelHorsepower: 300)]
        XCTAssertTrue(Steward.observe(v).contains { $0.ruleID == "build.quiet" })
    }

    func testLiveHighCoolantIsAdvisoryAndEstimated() {
        let frame = LiveTelemetryFrame(
            coolantTempF: TimedMeasurement(240, source: .simulated),
            connectionState: .polling)
        let obs = Steward.observe(frame: frame, for: vehicle())
        XCTAssertTrue(obs.contains { $0.tone == .advisory && $0.provenance == .estimatedLive })
    }

    func testObservationsOrderAdvisoryAboveInformational() {
        var v = vehicle([Part(name: "Turbo", category: .forcedInduction, status: .installed)])
        v.confirmedStockSystems = [.fueling]   // a real (strong caution) gap
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 350)]
        v.documentedTotalInvestment = 15_000   // informational cost fact
        let obs = Steward.observe(v)
        guard let firstInfoIndex = obs.firstIndex(where: { $0.tone == .informational }),
              let firstCautionIndex = obs.firstIndex(where: { $0.tone == .caution }) else {
            return XCTFail("expected both a caution and an informational observation")
        }
        XCTAssertLessThan(firstCautionIndex, firstInfoIndex, "cautions should rank above informational facts")
    }

    /// Deterministic identity: rebuilding the same model yields the same observation ids, so
    /// SwiftUI doesn't churn. And the sort is total (no ties left to chance).
    func testObservationIdentityIsDeterministic() {
        var v = vehicle([Part(name: "Turbo", category: .forcedInduction, status: .installed)])
        v.confirmedStockSystems = [.fueling, .cooling]
        let a = Steward.observe(v).map(\.id)
        let b = Steward.observe(v).map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a).count, a.count, "ids should be unique within one pass")
    }
}
