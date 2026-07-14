import XCTest
@testable import GarageHUDKit

/// The simulated feed is a deterministic settle/sweep/lift/cruise cycle, not a random walk, so a
/// Pull Guardian capture is guaranteed on a predictable clock — the exact thing a random walk can't
/// promise. This proves it end-to-end: feeding one full cycle's samples through the real
/// PullDetector must close a genuine pull, every time, without relying on chance.
final class DemoCycleTests: XCTestCase {
    private let envelope = OperatingEnvelope(
        boostCautionPsi: 12, maxSustainedBoostPsi: 20,
        expectedBoostByRPM: [BoostBand(rpmLow: 2000, rpmHigh: 7000, expectedLowPsi: 2, expectedHighPsi: 15)])

    private func tickTime(_ t: Int) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + Double(t) * 0.2) }

    private func frame(_ s: DemoSample, at t: Int) -> LiveTelemetryFrame {
        let now = tickTime(t)
        return LiveTelemetryFrame(
            rpm: TimedMeasurement(s.rpm, source: .simulated, at: now),
            speedMph: TimedMeasurement(s.speed, source: .simulated, at: now),
            coolantTempF: TimedMeasurement(190, source: .simulated, at: now),
            boostPsi: TimedMeasurement(s.boost, source: .simulated, at: now),
            throttlePercent: TimedMeasurement(s.throttle, source: .simulated, at: now),
            connectionState: .polling, capturedAt: now)
    }

    func testOneFullDemoCycleProducesExactlyOneClosedPull() {
        var detector = PullDetector(feedLabel: "Simulated", envelope: envelope)
        var reports: [PullReport] = []
        for tick in 0..<75 {
            if let report = detector.ingest(frame(demoSample(at: tick), at: tick), now: tickTime(tick)) {
                reports.append(report)
            }
        }
        XCTAssertEqual(reports.count, 1, "the sweep+lift shape must close exactly one pull per cycle")
        let report = reports[0]
        XCTAssertGreaterThan(report.rpmPeak - report.rpmStart, PullDetector.minRPMRise)
        XCTAssertEqual(report.confidence, .weak)   // fully simulated boost — never reads as Confirmed
    }

    func testTheSweepAloneClearsArmingThresholds() {
        // The sweep phase (10..<42) must stay above the 65% arming line and rise well past 400rpm —
        // demonstrated directly against the pure sample function, independent of the detector.
        let sweepSamples = (10..<42).map { demoSample(at: $0) }
        XCTAssertTrue(sweepSamples.allSatisfy { $0.throttle >= PullDetector.throttleOnThreshold })
        XCTAssertGreaterThanOrEqual(sweepSamples.last!.rpm - sweepSamples.first!.rpm, PullDetector.minRPMRise)
    }

    func testTheLiftPhaseDropsBelowTheClosingThreshold() {
        // The lift phase (42..<49) must actually cross below 35% so the run closes, not coast open.
        let liftSamples = (42..<49).map { demoSample(at: $0) }
        XCTAssertTrue(liftSamples.contains { $0.throttle < PullDetector.throttleOffThreshold })
    }

    func testMultipleConsecutiveCyclesEachProduceTheirOwnPull() {
        // Demoing for longer than one cycle (e.g. the owner leaves the tab open) must keep
        // producing fresh, independent pulls rather than stalling after the first.
        var detector = PullDetector(feedLabel: "Simulated", envelope: envelope)
        var reports: [PullReport] = []
        for tick in 0..<225 {   // three full cycles
            if let report = detector.ingest(frame(demoSample(at: tick % 75), at: tick), now: tickTime(tick)) {
                reports.append(report)
            }
        }
        XCTAssertEqual(reports.count, 3)
    }
}
