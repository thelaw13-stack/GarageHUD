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

/// Swap in a CoreBluetooth-backed ELM327 implementation later; views only depend on this protocol.
public protocol LiveDataSource: AnyObject {
    var metricsStream: AsyncStream<LiveMetrics> { get }
    func start()
    func stop()
}

/// Generates plausible wandering values so the Live Session HUD is demoable before real OBD-II hardware is wired in.
public final class SimulatedLiveDataSource: LiveDataSource {
    public let metricsStream: AsyncStream<LiveMetrics>
    private let continuation: AsyncStream<LiveMetrics>.Continuation
    private var task: Task<Void, Never>?

    public init() {
        var capturedContinuation: AsyncStream<LiveMetrics>.Continuation!
        self.metricsStream = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
    }

    public func start() {
        task?.cancel()
        let continuation = continuation
        task = Task {
            var rpm = 900.0
            var speed = 0.0
            var boost = 0.0
            var throttle = 0.0
            var coolant = 175.0
            while !Task.isCancelled {
                throttle = (throttle + Double.random(in: -18...22)).clamped(to: 0...100)
                rpm = (rpm + Double.random(in: -300...900) + throttle * 4).clamped(to: 800...7200)
                speed = (speed + Double.random(in: -4...7) + throttle * 0.05).clamped(to: 0...150)
                boost = (boost + Double.random(in: -2...3) + (throttle > 70 ? 1.5 : -1)).clamped(to: -6...20)
                coolant = (coolant + Double.random(in: -1...1)).clamped(to: 160...225)

                continuation.yield(
                    LiveMetrics(
                        rpm: rpm,
                        speedMph: speed,
                        coolantTempF: coolant,
                        boostPsi: boost,
                        throttlePercent: throttle
                    )
                )
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    /// Finishes the underlying AsyncStream for good; create a new instance to start another session.
    public func stop() {
        task?.cancel()
        task = nil
        continuation.finish()
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
