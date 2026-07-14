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

/// One instant in the deterministic demo cycle (see `demoSample(at:)`). A named, `Sendable` type
/// rather than a tuple, and free/top-level rather than nested — so nothing about it trips the
/// concurrency checker when it crosses into the source's streaming `Task` below.
struct DemoSample: Sendable, Equatable {
    let rpm: Double
    let speed: Double
    let boost: Double
    let throttle: Double
}

/// One full settle/sweep/lift/cruise cycle, in 200ms ticks (~15s total). Tuned so the sweep alone
/// clears `PullDetector`'s thresholds (throttle stays well above the 65% arming line for several
/// seconds, RPM rises far past the 400rpm floor) and the lift cleanly drops throttle below the 35%
/// closing line, so a Pull Guardian report reliably closes once per cycle.
private enum DemoCycle {
    static let ticksPerCycle = 75
    static let settle = 0..<10       // 2.0s: idle creeping toward the run
    static let sweep = 10..<42       // 6.4s: sustained wide-open throttle, RPM climbing
    static let lift = 42..<49        // 1.4s: throttle released, RPM falling — closes the pull
    // everything else: cool-down cruise back toward idle
}

/// The deterministic sample for a tick position within the cycle. Pure and free-standing so the
/// demo cycle's shape can be asserted directly in tests, not just observed end-to-end through the
/// async stream.
func demoSample(at phase: Int) -> DemoSample {
    switch phase {
    case DemoCycle.settle:
        let p = Double(phase) / Double(DemoCycle.settle.count)
        return DemoSample(rpm: 900 + p * 600, speed: 5 + p * 5, boost: -3, throttle: 10 + p * 8)
    case DemoCycle.sweep:
        let p = Double(phase - DemoCycle.sweep.lowerBound) / Double(DemoCycle.sweep.count)
        return DemoSample(rpm: 1_900 + p * 4_900, speed: 22 + p * 78, boost: 3 + p * 11, throttle: 80 + p * 12)
    case DemoCycle.lift:
        let p = Double(phase - DemoCycle.lift.lowerBound) / Double(DemoCycle.lift.count)
        return DemoSample(rpm: 6_800 - p * 4_300, speed: 100 - p * 15, boost: 14 - p * 16, throttle: 90 - p * 82)
    default:
        let p = Double(phase - DemoCycle.lift.upperBound) / Double(DemoCycle.ticksPerCycle - DemoCycle.lift.upperBound)
        return DemoSample(rpm: 2_500 - p * 1_400, speed: 85 - p * 60, boost: -2, throttle: 22 - p * 8)
    }
}

/// Generates a repeatable settle → loaded sweep → lift → cruise cycle so the whole Live workflow,
/// including a Pull Guardian capture, is demoable on a predictable clock before real OBD-II
/// hardware is connected — rather than waiting on a random walk to happen to produce a pull. Every
/// value it emits is still tagged `.simulated` and freshly timestamped — honest about being
/// invented, never mistaken for measured, and PullDetector grades a simulated pull accordingly
/// (never higher than "Weak" confidence — no capture is imitating real evidence).
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
        let ticksPerCycle = DemoCycle.ticksPerCycle
        task = Task {
            var tick = 0
            var coolant = 178.0
            while !Task.isCancelled {
                let s = demoSample(at: tick % ticksPerCycle)
                coolant = min(206, coolant + 0.03)   // creeps up over a cycle, never spikes on its own

                let now = Date()
                func m(_ v: Double) -> TimedMeasurement<Double> { TimedMeasurement(v, source: .simulated, at: now) }
                continuation.yield(LiveTelemetryFrame(
                    rpm: m(s.rpm), speedMph: m(s.speed), coolantTempF: m(coolant),
                    boostPsi: m(s.boost), throttlePercent: m(s.throttle),
                    connectionState: .polling, capturedAt: now))
                tick += 1
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
