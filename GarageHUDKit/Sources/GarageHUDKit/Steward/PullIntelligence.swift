import Foundation

/// A conservative reading of recent Pull Guardian reports. This is intentionally not an ECU
/// recommendation: standard OBD-II boost/coolant data cannot prove AFR, ignition timing, or knock.
/// It answers the narrower question GarageHUD can support honestly: are measured pulls tracking
/// the recorded target repeatably, and what should be verified before the next one?
public struct PullIntelligence: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case learning
        case stable
        case watch
        case hold

        public var label: String {
            switch self {
            case .learning: return "Learning"
            case .stable: return "Repeatable"
            case .watch: return "Review"
            case .hold: return "Stop"
            }
        }
    }

    public let state: State
    public let headline: String
    public let nextAction: String
    public let evidence: String
    public let totalPulls: Int
    public let measuredPulls: Int
    public let repeatabilitySpreadPsi: Double?
    public let averageTargetFit: Double?
    public let latestPeakDriftPsi: Double?

    public static func analyze(_ reports: [PullReport], limit: Int = 5) -> PullIntelligence {
        let recent = Array(reports.sorted { $0.endedAt > $1.endedAt }.prefix(limit))
        let measured = recent.filter {
            $0.confidence >= .moderate && ($0.measuredBoostFraction ?? 0) >= 0.4
        }
        let fitValues = measured.compactMap(\.onTargetFraction)
        let averageFit = fitValues.isEmpty ? nil : fitValues.reduce(0, +) / Double(fitValues.count)
        let peaks = measured.compactMap(\.boostPeakPsi)
        let spread = peaks.count >= 2 ? (peaks.max()! - peaks.min()!) : nil
        let latest = measured.first
        let priorPeaks = measured.dropFirst().compactMap(\.boostPeakPsi)
        let drift = latest?.boostPeakPsi.flatMap { peak in
            median(priorPeaks).map { peak - $0 }
        }

        if let latest, latest.boostBreachedCeiling {
            return result(
                state: .hold,
                headline: "The latest measured pull crossed the recorded boost ceiling.",
                action: "Stop loaded pulls. Inspect boost control and the recorded ceiling before another run.",
                evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
                recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
        }

        if let latest, let delta = latest.coolantDeltaF, delta >= 15 {
            return result(
                state: .hold,
                headline: "The latest measured pull added \(format(delta))°F of coolant temperature.",
                action: "Let the car recover and verify the cooling system before repeating the load.",
                evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
                recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
        }

        if let latest, (latest.overTargetFraction ?? 0) >= 0.5 {
            return result(
                state: .watch,
                headline: "The latest measured pull spent most of its mapped samples above target.",
                action: "Review boost control and map intent. Do not repeat the pull at full load until the cause is understood.",
                evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
                recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
        }

        if let latest, (latest.underTargetFraction ?? 0) >= 0.5 {
            return result(
                state: .watch,
                headline: "The latest measured pull spent most of its mapped samples below target.",
                action: "Check for leaks, throttle closure, or boost-control limits before changing the tune.",
                evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
                recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
        }

        if let spread, spread > 2.0 {
            return result(
                state: .watch,
                headline: "Recent measured boost peaks are not yet repeatable.",
                action: "Repeat only under matched conditions and inspect control behavior before drawing a tuning conclusion.",
                evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
                recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
        }

        if measured.count >= 2, let averageFit, averageFit >= 0.75 {
            return result(
                state: .stable,
                headline: "Recent measured pulls are tracking the recorded boost envelope repeatably.",
                action: "Preserve the current map and keep watching thermal recovery. AFR and knock still require dedicated signals.",
                evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
                recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
        }

        let action = recent.isEmpty
            ? "Capture a controlled pull with the OBDLink CX to establish a measured baseline."
            : "Capture at least two OBDLink pulls under matched conditions; simulated runs do not establish tune safety."
        return result(
            state: .learning,
            headline: measured.isEmpty
                ? "No measured pull baseline is available yet."
                : "More matched measured pulls are needed before calling the boost behavior repeatable.",
            action: action,
            evidence: evidence(recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift),
            recent: recent, measured: measured, spread: spread, fit: averageFit, drift: drift)
    }

    private static func result(state: State, headline: String, action: String, evidence: String,
                               recent: [PullReport], measured: [PullReport], spread: Double?,
                               fit: Double?, drift: Double?) -> PullIntelligence {
        PullIntelligence(state: state, headline: headline, nextAction: action, evidence: evidence,
                         totalPulls: recent.count, measuredPulls: measured.count,
                         repeatabilitySpreadPsi: spread, averageTargetFit: fit,
                         latestPeakDriftPsi: drift)
    }

    private static func evidence(recent: [PullReport], measured: [PullReport], spread: Double?,
                                 fit: Double?, drift: Double?) -> String {
        var pieces = ["Using \(measured.count) measured of \(recent.count) recent pull\(recent.count == 1 ? "" : "s")"]
        if let fit { pieces.append("average target fit \(Int((fit * 100).rounded()))%") }
        if let spread { pieces.append("peak spread \(format(spread)) psi") }
        if let drift {
            pieces.append("latest peak \(drift >= 0 ? "+" : "")\(format(drift)) psi vs prior median")
        }
        return pieces.joined(separator: "; ") + "."
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[middle - 1] + sorted[middle]) / 2 }
        return sorted[middle]
    }

    private static func format(_ value: Double) -> String { String(format: "%.1f", value) }
}
