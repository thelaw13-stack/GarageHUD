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

/// A repeatable garage demo: idle, one deliberate pull, recovery, then cruise. The fixed shape
/// exercises the same detector thresholds on every run and makes visual review reproducible.
struct SimulatedDemoCycle: Sendable {
    static let frameCount = 60
    static let interval: TimeInterval = 0.2

    static func frame(at rawIndex: Int, timestamp: Date) -> LiveTelemetryFrame {
        let index = rawIndex % frameCount
        let rpm: Double
        let speed: Double
        let boost: Double
        let throttle: Double
        let coolant: Double

        switch index {
        case 0..<10:
            rpm = 950 + Double(index) * 16
            speed = 4
            boost = -2.5
            throttle = 11
            coolant = 178 + Double(index) * 0.08
        case 10..<30:
            let progress = Double(index - 10) / 19
            rpm = 2400 + progress * 3900
            speed = 28 + progress * 56
            boost = 4 + progress * 9
            throttle = 88
            coolant = 180 + progress * 4
        case 30:
            rpm = 6350
            speed = 86
            boost = 2
            throttle = 14
            coolant = 184
        default:
            let recovery = Double(index - 31)
            rpm = max(1700, 3500 - recovery * 70)
            speed = max(32, 82 - recovery * 1.8)
            boost = -1.5
            throttle = 18
            coolant = max(181, 184 - recovery * 0.12)
        }

        func measurement(_ value: Double) -> TimedMeasurement<Double> {
            TimedMeasurement(value, source: .simulated, at: timestamp)
        }
        return LiveTelemetryFrame(
            rpm: measurement(rpm), speedMph: measurement(speed),
            coolantTempF: measurement(coolant), boostPsi: measurement(boost),
            throttlePercent: measurement(throttle), connectionState: .polling,
            capturedAt: timestamp)
    }
}

/// Generates deterministic demo values before real OBD-II hardware is connected. Every value
/// is tagged `.simulated` and freshly timestamped: useful for rehearsal, never mistaken for
/// measured evidence.
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
            var index = 0
            while !Task.isCancelled {
                continuation.yield(SimulatedDemoCycle.frame(at: index, timestamp: .now))
                index = (index + 1) % SimulatedDemoCycle.frameCount
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
