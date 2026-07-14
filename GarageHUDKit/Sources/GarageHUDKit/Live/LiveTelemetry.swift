import Foundation

/// Where a single value actually came from. This is the honesty pivot: a number is only
/// "measured" if it was decoded from a real adapter reply — never because the *transport*
/// happened to be Bluetooth.
public enum MeasurementSource: Sendable, Equatable {
    case simulated      // generated locally for demo/estimation
    case obdAdapter     // decoded from an actual OBD-II PID response
}

/// One value with the two facts that decide how much we may trust it: when it arrived and
/// where it came from. A value with no recent `TimedMeasurement` is *unavailable*, not
/// "the last thing we saw."
public struct TimedMeasurement<Value: Sendable>: Sendable {
    public let value: Value
    public let receivedAt: Date
    public let source: MeasurementSource

    public init(_ value: Value, source: MeasurementSource, at receivedAt: Date = .now) {
        self.value = value
        self.source = source
        self.receivedAt = receivedAt
    }

    public func age(now: Date = .now) -> TimeInterval { now.timeIntervalSince(receivedAt) }

    /// Fresh = arrived within the window and not from the future (clock skew guard).
    public func isFresh(within window: TimeInterval, now: Date = .now) -> Bool {
        let a = age(now: now)
        return a >= 0 && a <= window
    }
}

/// How long a telemetry value stays trustworthy after it last arrived. Past this, the value
/// is treated as unavailable rather than retained — so a PID that stops responding stops
/// being reported, instead of freezing at its last reading.
public enum LiveFreshness {
    public static let window: TimeInterval = 2.0
}

/// The explicit connection lifecycle of an OBD adapter link. The UI reflects this directly
/// so "measured" is never claimed while the link is anything but genuinely polling.
public enum OBDConnectionState: Equatable, Sendable {
    case disconnected
    case scanning
    case connecting
    case discoveringServices
    case discoveringCharacteristics
    case resetting          // ATZ sent, waiting for the adapter to come up
    case configuring        // running ATE0/ATL0/ATH0/ATSP0
    case ready              // protocol negotiated, not yet polling
    case polling            // actively reading PIDs
    case degraded           // responses failing; values going stale
    case reconnecting

    /// The only state in which adapter values may be treated as live/measured.
    public var isLive: Bool { self == .polling }
}

/// Human-readable progress from the adapter transport. This travels with each frame so the Live
/// screen can explain exactly where a connection is, which device was seen, and what the owner can
/// do next. It deliberately contains no raw Bluetooth identifiers or opaque error codes.
public struct OBDConnectionDetail: Equatable, Sendable {
    public var adapterName: String?
    public var message: String
    public var recovery: String?
    public var attempt: Int

    public init(adapterName: String? = nil, message: String,
                recovery: String? = nil, attempt: Int = 0) {
        self.adapterName = adapterName
        self.message = message
        self.recovery = recovery
        self.attempt = attempt
    }
}

/// A snapshot of the live feed: each metric independently timestamped and sourced, plus the
/// link state. Nothing here asserts a value is current — the reader decides that with a
/// freshness window, which is exactly the point.
public struct LiveTelemetryFrame: Sendable {
    public var rpm: TimedMeasurement<Double>?
    public var speedMph: TimedMeasurement<Double>?
    public var coolantTempF: TimedMeasurement<Double>?
    public var boostPsi: TimedMeasurement<Double>?
    public var throttlePercent: TimedMeasurement<Double>?
    public var connectionState: OBDConnectionState
    public var connectionDetail: OBDConnectionDetail?
    public var capturedAt: Date

    public init(rpm: TimedMeasurement<Double>? = nil,
                speedMph: TimedMeasurement<Double>? = nil,
                coolantTempF: TimedMeasurement<Double>? = nil,
                boostPsi: TimedMeasurement<Double>? = nil,
                throttlePercent: TimedMeasurement<Double>? = nil,
                connectionState: OBDConnectionState = .disconnected,
                connectionDetail: OBDConnectionDetail? = nil,
                capturedAt: Date = .now) {
        self.rpm = rpm
        self.speedMph = speedMph
        self.coolantTempF = coolantTempF
        self.boostPsi = boostPsi
        self.throttlePercent = throttlePercent
        self.connectionState = connectionState
        self.connectionDetail = connectionDetail
        self.capturedAt = capturedAt
    }

    /// The fresh measurement for a metric, or nil if it's stale/absent.
    public func fresh(_ metric: KeyPath<LiveTelemetryFrame, TimedMeasurement<Double>?>,
                      window: TimeInterval = LiveFreshness.window, now: Date = .now) -> TimedMeasurement<Double>? {
        guard let m = self[keyPath: metric], m.isFresh(within: window, now: now) else { return nil }
        return m
    }

    /// A plain `LiveMetrics` for gauges/records. Uses only *fresh* values; anything stale or
    /// missing falls back to the previous displayed value (so the needle doesn't snap to
    /// zero), while `staleMetrics` tells the UI which needles can't be trusted right now.
    public func displaySnapshot(carryingOver previous: LiveMetrics?,
                                window: TimeInterval = LiveFreshness.window, now: Date = .now) -> LiveMetrics {
        func pick(_ kp: KeyPath<LiveTelemetryFrame, TimedMeasurement<Double>?>, _ fallback: Double) -> Double {
            fresh(kp, window: window, now: now)?.value ?? fallback
        }
        return LiveMetrics(
            rpm: pick(\.rpm, previous?.rpm ?? 0),
            speedMph: pick(\.speedMph, previous?.speedMph ?? 0),
            coolantTempF: pick(\.coolantTempF, previous?.coolantTempF ?? 0),
            boostPsi: pick(\.boostPsi, previous?.boostPsi ?? 0),
            throttlePercent: pick(\.throttlePercent, previous?.throttlePercent ?? 0),
            timestamp: capturedAt)
    }

    /// True when there's at least one fresh value to speak of.
    public func hasAnyFresh(window: TimeInterval = LiveFreshness.window, now: Date = .now) -> Bool {
        [\LiveTelemetryFrame.rpm, \.speedMph, \.coolantTempF, \.boostPsi, \.throttlePercent]
            .contains { fresh($0, window: window, now: now) != nil }
    }
}
