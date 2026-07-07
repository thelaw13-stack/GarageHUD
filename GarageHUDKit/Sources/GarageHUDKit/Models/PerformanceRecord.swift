import Foundation

public struct PerformanceRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = .now
    public var type: PerformanceType
    public var wheelHorsepower: Double?
    public var wheelTorque: Double?
    public var elapsedTimeSeconds: Double?
    public var trapSpeedMph: Double?
    public var lapTimeSeconds: Double?
    public var location: String = ""
    public var notes: String = ""
    public var isFromLiveSession: Bool = false
    public var capturedPoints: [LiveMetrics] = []

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        type: PerformanceType,
        wheelHorsepower: Double? = nil,
        wheelTorque: Double? = nil,
        elapsedTimeSeconds: Double? = nil,
        trapSpeedMph: Double? = nil,
        lapTimeSeconds: Double? = nil,
        location: String = "",
        notes: String = "",
        isFromLiveSession: Bool = false,
        capturedPoints: [LiveMetrics] = []
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.wheelHorsepower = wheelHorsepower
        self.wheelTorque = wheelTorque
        self.elapsedTimeSeconds = elapsedTimeSeconds
        self.trapSpeedMph = trapSpeedMph
        self.lapTimeSeconds = lapTimeSeconds
        self.location = location
        self.notes = notes
        self.isFromLiveSession = isFromLiveSession
        self.capturedPoints = capturedPoints
    }

    public var summary: String {
        switch type {
        case .dyno:
            if let hp = wheelHorsepower { return "\(Int(hp)) whp" }
        case .quarterMile:
            if let et = elapsedTimeSeconds { return String(format: "%.2fs @ %.0f mph", et, trapSpeedMph ?? 0) }
        case .zeroToSixty:
            if let et = elapsedTimeSeconds { return String(format: "%.2fs 0-60", et) }
        case .lapTime:
            if let lap = lapTimeSeconds { return String(format: "%.2fs lap", lap) }
        case .boostLog, .custom:
            break
        }
        return type.rawValue
    }
}
