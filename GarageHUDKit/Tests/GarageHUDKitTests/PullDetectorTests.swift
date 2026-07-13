import XCTest
@testable import GarageHUDKit

/// Pull Guardian: detects a genuine wide-open-throttle pull from a live telemetry stream and grades
/// its own boost claims by how much of the data was actually measured — never a blip, never more
/// certain than the evidence behind it.
final class PullDetectorTests: XCTestCase {
    private let envelope = OperatingEnvelope(
        boostCautionPsi: 12, maxSustainedBoostPsi: 14,
        expectedBoostByRPM: [BoostBand(rpmLow: 3000, rpmHigh: 7000, expectedLowPsi: 9, expectedHighPsi: 12)])

    private func frame(t: TimeInterval, rpm: Double, throttle: Double, boost: Double? = nil,
                       coolant: Double? = nil, boostMeasured: Bool = true) -> LiveTelemetryFrame {
        let now = Date(timeIntervalSince1970: 1_700_000_000 + t)
        return LiveTelemetryFrame(
            rpm: TimedMeasurement(rpm, source: .simulated, at: now),
            coolantTempF: coolant.map { TimedMeasurement($0, source: .simulated, at: now) },
            boostPsi: boost.map { TimedMeasurement($0, source: boostMeasured ? .obdAdapter : .simulated, at: now) },
            throttlePercent: TimedMeasurement(throttle, source: .simulated, at: now),
            connectionState: .polling, capturedAt: now)
    }

    private func now(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: 1_700_000_000 + t) }

    // MARK: Detection shape

    func testGenuinePullClosesOnThrottleLift() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        var report: PullReport?
        for t in stride(from: 0.0, through: 3.0, by: 0.5) {
            let rpm = 3000 + t * 1200   // rises to ~6600 rpm over 3s
            report = d.ingest(frame(t: t, rpm: rpm, throttle: 90, boost: 10), now: now(t))
        }
        XCTAssertNil(report)   // still WOT — not closed yet
        report = d.ingest(frame(t: 3.5, rpm: 6800, throttle: 10), now: now(3.5))   // throttle lifts
        XCTAssertNotNil(report)
        XCTAssertEqual(report!.rpmStart, 3000, accuracy: 1)
        XCTAssertGreaterThan(report!.rpmPeak, 6000)
    }

    func testThrottleBlipTooShortIsDiscarded() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        _ = d.ingest(frame(t: 0, rpm: 3000, throttle: 90, boost: 10), now: now(0))
        // Lifts after only 0.5s — below minDuration.
        let report = d.ingest(frame(t: 0.5, rpm: 3200, throttle: 10), now: now(0.5))
        XCTAssertNil(report)
    }

    func testShallowRPMRiseIsDiscardedEvenIfLongEnough() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        // 3 seconds of throttle but RPM barely moves (e.g. already at redline / clutch slip).
        for t in stride(from: 0.0, through: 3.0, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 6900 + t, throttle: 90, boost: 10), now: now(t))
        }
        let report = d.ingest(frame(t: 3.5, rpm: 6903, throttle: 10), now: now(3.5))
        XCTAssertNil(report)
    }

    func testStaleThrottleClosesARunJustLikeALift() {
        // A dropped/degraded link must not let a run coast open forever.
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        for t in stride(from: 0.0, through: 3.0, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90, boost: 10), now: now(t))
        }
        // Next frame has no throttle measurement at all (stale/dropped).
        let staleFrame = LiveTelemetryFrame(
            rpm: TimedMeasurement(6500, source: .simulated, at: now(3.5)),
            connectionState: .degraded, capturedAt: now(3.5))
        let report = d.ingest(staleFrame, now: now(3.5))
        XCTAssertNotNil(report)
    }

    // MARK: Boost verdict + confidence

    func testCeilingBreachIsFlagged() {
        var d = PullDetector(feedLabel: "OBD-II Adapter", envelope: envelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            let boost = t >= 2.0 ? 15.0 : 10.0   // spikes over the 14 psi ceiling near the end
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90, boost: boost), now: now(t))
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5500, throttle: 10), now: now(3.0))!
        XCTAssertTrue(report.boostBreachedCeiling)
        XCTAssertEqual(report.boostCeilingPsi, 14)
        XCTAssertTrue(report.verdictStatement.localizedCaseInsensitiveContains("ceiling"))
    }

    func testFullyMeasuredBoostGradesConfirmed() {
        var d = PullDetector(feedLabel: "OBD-II Adapter", envelope: envelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90, boost: 10, boostMeasured: true), now: now(t))
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5500, throttle: 10), now: now(3.0))!
        XCTAssertEqual(report.confidence, .confirmed)
        XCTAssertEqual(report.measuredBoostFraction, 1.0)
    }

    func testFullySimulatedBoostGradesWeak() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90, boost: 10, boostMeasured: false), now: now(t))
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5500, throttle: 10), now: now(3.0))!
        XCTAssertEqual(report.confidence, .weak)
        XCTAssertEqual(report.measuredBoostFraction, 0.0)
    }

    func testNoBoostSignalGradesInsufficientButStillCapturesRPM() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90), now: now(t))   // no boost at all (NA car)
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5500, throttle: 10), now: now(3.0))!
        XCTAssertEqual(report.confidence, .insufficient)
        XCTAssertNil(report.boostPeakPsi)
        XCTAssertNil(report.measuredBoostFraction)
        XCTAssertGreaterThan(report.rpmPeak, report.rpmStart)   // RPM data still real and useful
    }

    func testOverTargetBandTracked() {
        var d = PullDetector(feedLabel: "OBD-II Adapter", envelope: envelope)
        // Band is 3000-7000 rpm expecting 9-12 psi; run consistently at 13 psi → over target.
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3500 + t * 500, throttle: 90, boost: 13), now: now(t))
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5000, throttle: 10), now: now(3.0))!
        XCTAssertEqual(report.overTargetFraction, 1.0)
        XCTAssertEqual(report.onTargetFraction, 0.0)
    }

    func testNoTuneProfileLeavesTargetFractionsNil() {
        let bareEnvelope = OperatingEnvelope(boostCautionPsi: 12, maxSustainedBoostPsi: 14)   // no bands
        var d = PullDetector(feedLabel: "OBD-II Adapter", envelope: bareEnvelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3500 + t * 500, throttle: 90, boost: 10), now: now(t))
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5000, throttle: 10), now: now(3.0))!
        XCTAssertNil(report.onTargetFraction)
        XCTAssertNil(report.overTargetFraction)
    }

    func testCoolantDeltaTrackedAcrossThePull() {
        var d = PullDetector(feedLabel: "OBD-II Adapter", envelope: envelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3500 + t * 500, throttle: 90, boost: 10, coolant: 195 + t), now: now(t))
        }
        let report = d.ingest(frame(t: 3.0, rpm: 5000, throttle: 10), now: now(3.0))!
        XCTAssertNotNil(report.coolantDeltaF)
        XCTAssertGreaterThan(report.coolantDeltaF!, 0)
    }

    // MARK: Live in-progress state (for the cockpit's "watching vs. capturing" readout)

    func testIsCapturingReflectsAnOpenRunOnly() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        XCTAssertFalse(d.isCapturing)
        _ = d.ingest(frame(t: 0, rpm: 3000, throttle: 90, boost: 10), now: now(0))
        XCTAssertTrue(d.isCapturing)
        _ = d.ingest(frame(t: 2.5, rpm: 5500, throttle: 10), now: now(2.5))   // closes the run
        XCTAssertFalse(d.isCapturing)
    }

    func testActiveSampleCountTracksTheOpenRunAndResetsAfterClose() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        XCTAssertEqual(d.activeSampleCount, 0)
        for (i, t) in stride(from: 0.0, through: 2.0, by: 0.5).enumerated() {
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90, boost: 10), now: now(t))
            XCTAssertEqual(d.activeSampleCount, i + 1)
        }
        _ = d.ingest(frame(t: 2.5, rpm: 5500, throttle: 10), now: now(2.5))   // closes the run
        XCTAssertEqual(d.activeSampleCount, 0, "must not show a stale count once capture has ended")
    }

    func testActiveRPMStartIsNilWhenNotCapturing() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        XCTAssertNil(d.activeRPMStart)
        _ = d.ingest(frame(t: 0, rpm: 3200, throttle: 90, boost: 10), now: now(0))
        XCTAssertEqual(d.activeRPMStart, 3200)
    }

    func testDetectorResetsCleanlyForANewPullAfterOne() {
        var d = PullDetector(feedLabel: "Simulated", envelope: envelope)
        for t in stride(from: 0.0, through: 2.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 3000 + t * 1000, throttle: 90, boost: 10), now: now(t))
        }
        _ = d.ingest(frame(t: 3.0, rpm: 5500, throttle: 10), now: now(3.0))   // closes pull #1

        // A second, independent pull should be detected on its own terms.
        for t in stride(from: 4.0, through: 6.5, by: 0.5) {
            _ = d.ingest(frame(t: t, rpm: 2000 + (t - 4) * 1000, throttle: 95, boost: 8), now: now(t))
        }
        let second = d.ingest(frame(t: 7.0, rpm: 4500, throttle: 5), now: now(7.0))
        XCTAssertNotNil(second)
        XCTAssertEqual(second!.rpmStart, 2000, accuracy: 1)   // fresh baseline, not pull #1's
    }
}
