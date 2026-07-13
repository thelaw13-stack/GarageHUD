import Foundation

/// Watches a live telemetry stream for a genuine wide-open-throttle pull — sustained, not a
/// throttle blip — and closes it into a `PullReport` graded by how much of the boost data behind
/// it was actually measured. Pure state machine: feed it frames one at a time, get a report back
/// exactly when a run completes. Works identically over the simulated and adapter feeds, since it
/// only reasons about frame content, not where the frame came from — which is also why the
/// simulated feed can fully exercise this before an adapter is on hand.
public struct PullDetector: Sendable {
    /// Throttle level that starts a candidate run.
    public static let throttleOnThreshold: Double = 65
    /// Throttle level a run must drop below to end (a gap below the "on" threshold so a wavering
    /// foot near 60% doesn't chatter the detector open/closed).
    public static let throttleOffThreshold: Double = 35
    /// Minimum duration for a candidate run to count as a genuine pull, not a blip.
    public static let minDuration: TimeInterval = 2.0
    /// Minimum RPM rise for a candidate run to count as a genuine pull, not idle throttle noise.
    public static let minRPMRise: Double = 400

    private var runStart: Date?
    private var rpmStart: Double = 0
    private var rpmPeak: Double = 0
    private var rpmLast: Double = 0
    private var boostPeak: Double?
    private var boostCeilingBreached = false
    private var coolantStart: Double?
    private var coolantPeak: Double?
    private var coolantLast: Double?
    private var sampleCount = 0
    private var boostSamples = 0
    private var measuredBoostSamples = 0
    private var bandedSamples = 0
    private var onTargetSamples = 0
    private var overTargetSamples = 0
    private var underTargetSamples = 0

    private let feedLabel: String
    private let envelope: OperatingEnvelope

    public init(feedLabel: String, envelope: OperatingEnvelope) {
        self.feedLabel = feedLabel
        self.envelope = envelope
    }

    /// Feed one frame. Returns a finished report exactly when a genuine pull just closed — nil
    /// while mid-run, at idle, or when a throttle blip was too short/shallow to count.
    public mutating func ingest(_ frame: LiveTelemetryFrame, now: Date = .now) -> PullReport? {
        let throttle = frame.fresh(\.throttlePercent, now: now)?.value

        guard runStart != nil else {
            // Not currently in a run — does this frame start one?
            guard let throttle, throttle >= Self.throttleOnThreshold,
                  let rpm = frame.fresh(\.rpm, now: now)?.value else { return nil }
            beginRun(at: now, rpm: rpm)
            accumulate(frame, now: now)
            return nil
        }

        // In a run — a fresh throttle reading still above the off-threshold continues it.
        // A stale or dropped-below reading closes it (never let a run coast on missing data).
        if let throttle, throttle >= Self.throttleOffThreshold {
            accumulate(frame, now: now)
            return nil
        }
        return closeRun(now: now)
    }

    private mutating func beginRun(at now: Date, rpm: Double) {
        runStart = now
        rpmStart = rpm; rpmPeak = rpm; rpmLast = rpm
        boostPeak = nil; boostCeilingBreached = false
        coolantStart = nil; coolantPeak = nil; coolantLast = nil
        sampleCount = 0; boostSamples = 0; measuredBoostSamples = 0
        bandedSamples = 0; onTargetSamples = 0; overTargetSamples = 0; underTargetSamples = 0
    }

    private mutating func accumulate(_ frame: LiveTelemetryFrame, now: Date) {
        sampleCount += 1
        let rpmNow = frame.fresh(\.rpm, now: now)?.value
        if let rpmNow { rpmPeak = max(rpmPeak, rpmNow); rpmLast = rpmNow }

        if let boostM = frame.fresh(\.boostPsi, now: now) {
            boostSamples += 1
            if boostM.source == .obdAdapter { measuredBoostSamples += 1 }
            boostPeak = max(boostPeak ?? -.infinity, boostM.value)
            if let ceiling = envelope.maxSustainedBoostPsi, boostM.value > ceiling {
                boostCeilingBreached = true
            }
            if let rpmNow, let band = envelope.expectedBoostByRPM.first(where: { $0.contains(rpm: rpmNow) }) {
                bandedSamples += 1
                if boostM.value > band.expectedHighPsi { overTargetSamples += 1 }
                else if boostM.value < band.expectedLowPsi { underTargetSamples += 1 }
                else { onTargetSamples += 1 }
            }
        }

        if let coolantM = frame.fresh(\.coolantTempF, now: now) {
            if coolantStart == nil { coolantStart = coolantM.value }
            coolantPeak = max(coolantPeak ?? -.infinity, coolantM.value)
            coolantLast = coolantM.value
        }
    }

    private mutating func closeRun(now: Date) -> PullReport? {
        defer { runStart = nil }
        guard let start = runStart else { return nil }

        // Discard noise: too brief or too shallow to be a genuine pull, not a real run.
        guard now.timeIntervalSince(start) >= Self.minDuration,
              rpmPeak - rpmStart >= Self.minRPMRise else { return nil }

        var measuredFraction: Double?
        let confidence: ConfidenceBand
        if boostSamples == 0 {
            confidence = .insufficient   // no boost signal at all — can't grade the boost claims
        } else {
            let frac = Double(measuredBoostSamples) / Double(boostSamples)
            measuredFraction = frac
            switch frac {
            case 1.0: confidence = .confirmed
            case 0.75...: confidence = .strong
            case 0.4..<0.75: confidence = .moderate
            case 0..<0.4: confidence = .weak
            default: confidence = .insufficient
            }
        }

        return PullReport(
            startedAt: start, endedAt: now, feedLabel: feedLabel,
            rpmStart: rpmStart, rpmPeak: rpmPeak, rpmEnd: rpmLast,
            boostPeakPsi: boostPeak, boostBreachedCeiling: boostCeilingBreached,
            boostCeilingPsi: envelope.maxSustainedBoostPsi,
            onTargetFraction: bandedSamples > 0 ? Double(onTargetSamples) / Double(bandedSamples) : nil,
            overTargetFraction: bandedSamples > 0 ? Double(overTargetSamples) / Double(bandedSamples) : nil,
            underTargetFraction: bandedSamples > 0 ? Double(underTargetSamples) / Double(bandedSamples) : nil,
            coolantStartF: coolantStart, coolantPeakF: coolantPeak,
            coolantDeltaF: (coolantStart != nil && coolantLast != nil) ? coolantLast! - coolantStart! : nil,
            sampleCount: sampleCount, measuredBoostFraction: measuredFraction, confidence: confidence)
    }
}
