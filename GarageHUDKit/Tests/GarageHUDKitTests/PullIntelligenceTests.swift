import XCTest
@testable import GarageHUDKit

final class PullIntelligenceTests: XCTestCase {
    private func report(index: Int, peak: Double = 12, on: Double = 0.9,
                        over: Double = 0.05, under: Double = 0.05,
                        breach: Bool = false, coolantDelta: Double = 3,
                        confidence: ConfidenceBand = .confirmed,
                        measured: Double = 1) -> PullReport {
        let end = Date(timeIntervalSince1970: 1_700_000_000 + Double(index * 60))
        return PullReport(
            startedAt: end.addingTimeInterval(-3), endedAt: end, feedLabel: "OBD-II Adapter",
            rpmStart: 3000, rpmPeak: 6500, rpmEnd: 6400,
            boostPeakPsi: peak, boostBreachedCeiling: breach, boostCeilingPsi: 14,
            onTargetFraction: on, overTargetFraction: over, underTargetFraction: under,
            coolantStartF: 190, coolantPeakF: 190 + coolantDelta, coolantDeltaF: coolantDelta,
            sampleCount: 20, measuredBoostFraction: measured, confidence: confidence)
    }

    func testTwoTightOnTargetMeasuredPullsAreRepeatable() {
        let result = PullIntelligence.analyze([report(index: 1, peak: 11.8), report(index: 2, peak: 12.2)])
        XCTAssertEqual(result.state, .stable)
        XCTAssertEqual(result.measuredPulls, 2)
        XCTAssertEqual(result.repeatabilitySpreadPsi!, 0.4, accuracy: 0.01)
    }

    func testLatestCeilingBreachStopsEvenWhenPriorPullWasClean() {
        let result = PullIntelligence.analyze([
            report(index: 1), report(index: 2, peak: 15, on: 0, over: 1, under: 0, breach: true)
        ])
        XCTAssertEqual(result.state, .hold)
        XCTAssertTrue(result.nextAction.localizedCaseInsensitiveContains("stop"))
    }

    func testLargePeakSpreadRequestsReview() {
        let result = PullIntelligence.analyze([report(index: 1, peak: 10), report(index: 2, peak: 13)])
        XCTAssertEqual(result.state, .watch)
        XCTAssertEqual(result.repeatabilitySpreadPsi, 3)
    }

    func testSimulatedPullsNeverCreateMeasuredBaseline() {
        let result = PullIntelligence.analyze([
            report(index: 1, confidence: .weak, measured: 0),
            report(index: 2, confidence: .weak, measured: 0)
        ])
        XCTAssertEqual(result.state, .learning)
        XCTAssertEqual(result.measuredPulls, 0)
    }

    func testThermalRiseStopsAnotherPull() {
        let result = PullIntelligence.analyze([report(index: 1, coolantDelta: 16)])
        XCTAssertEqual(result.state, .hold)
        XCTAssertTrue(result.headline.localizedCaseInsensitiveContains("coolant"))
    }
}
