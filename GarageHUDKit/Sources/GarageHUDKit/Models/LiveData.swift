import Foundation

public struct LiveMetrics: Codable, Hashable, Sendable {
    public var rpm: Double
    public var speedMph: Double
    public var coolantTempF: Double
    public var boostPsi: Double
    public var throttlePercent: Double
    public var timestamp: Date

    public init(
        rpm: Double,
        speedMph: Double,
        coolantTempF: Double,
        boostPsi: Double,
        throttlePercent: Double,
        timestamp: Date = .now
    ) {
        self.rpm = rpm
        self.speedMph = speedMph
        self.coolantTempF = coolantTempF
        self.boostPsi = boostPsi
        self.throttlePercent = throttlePercent
        self.timestamp = timestamp
    }
}

/// A source of live telemetry frames. Each metric in a frame carries its own timestamp and
/// source (see `LiveTelemetryFrame`), so consumers judge freshness rather than trusting the
/// transport wholesale.
///
/// **Lifecycle (reusable):** `stop()` halts transport and polling but leaves the frame stream
/// open, so the same source can be `start()`ed again (view reappears, app resumes, adapter
/// reconnects) and existing subscribers keep receiving. The stream is finished exactly once,
/// in `deinit`. Views may also create a fresh source per session; both are safe.
public protocol LiveDataSource: AnyObject {
    var frames: AsyncStream<LiveTelemetryFrame> { get }
    var connectionState: OBDConnectionState { get }
    func start()
    func stop()
}

/// Generates plausible wandering values so the Live HUD is demoable before real OBD-II
/// hardware is connected. Every value it emits is tagged `.simulated` and freshly timestamped
/// — honest about being invented, never mistaken for measured.
public final class SimulatedLiveDataSource: LiveDataSource {
    public let frames: AsyncStream<LiveTelemetryFrame>
    private let continuation: AsyncStream<LiveTelemetryFrame>.Continuation
    private var task: Task<Void, Never>?
    public private(set) var connectionState: OBDConnectionState = .disconnected

    public init() {
        var captured: AsyncStream<LiveTelemetryFrame>.Continuation!
        self.frames = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    public func start() {
        task?.cancel()
        connectionState = .polling
        let continuation = continuation
        task = Task {
            var rpm = 900.0, speed = 0.0, boost = 0.0, throttle = 0.0, coolant = 175.0
            while !Task.isCancelled {
                throttle = (throttle + Double.random(in: -18...22)).clamped(to: 0...100)
                rpm = (rpm + Double.random(in: -300...900) + throttle * 4).clamped(to: 800...7200)
                speed = (speed + Double.random(in: -4...7) + throttle * 0.05).clamped(to: 0...150)
                boost = (boost + Double.random(in: -2...3) + (throttle > 70 ? 1.5 : -1)).clamped(to: -6...20)
                coolant = (coolant + Double.random(in: -1...1)).clamped(to: 160...225)

                let now = Date()
                func m(_ v: Double) -> TimedMeasurement<Double> { TimedMeasurement(v, source: .simulated, at: now) }
                continuation.yield(LiveTelemetryFrame(
                    rpm: m(rpm), speedMph: m(speed), coolantTempF: m(coolant),
                    boostPsi: m(boost), throttlePercent: m(throttle),
                    connectionState: .polling, capturedAt: now))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// Stops producing but keeps the stream open so the source can be restarted.
    public func stop() {
        task?.cancel()
        task = nil
        connectionState = .disconnected
    }

    deinit { continuation.finish() }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
