import Foundation

/// Whether a vehicle is currently operational or intentionally out of service (a teardown,
/// rebuild, or major job). This matters to the Steward: a car that's apart on purpose isn't
/// "neglected", and the freshness/quiet rules must not scold the owner for it.
///
/// Modeled as a flat struct (not an enum with associated values) so it serializes to simple,
/// hand-editable JSON and decodes with a sensible default from older records.
public struct ServiceStatus: Codable, Hashable, Sendable {
    public var isInService: Bool
    /// Short reason shown to the owner, e.g. "Engine teardown — internals under inspection".
    public var reason: String
    /// When the vehicle went out of service, if recorded.
    public var since: Date?
    /// What's left to finish before the car is back on the road.
    public var checklist: [ServiceTask]

    public init(isInService: Bool = false, reason: String = "", since: Date? = nil,
                checklist: [ServiceTask] = []) {
        self.isInService = isInService
        self.reason = reason
        self.since = since
        self.checklist = checklist
    }

    public static var operational: ServiceStatus { ServiceStatus() }

    public var completedCount: Int { checklist.filter(\.isDone).count }
    /// e.g. "2 of 5 done", or nil when there's no checklist.
    public var progressText: String? {
        guard !checklist.isEmpty else { return nil }
        return "\(completedCount) of \(checklist.count) done"
    }
}

/// One item on a rebuild/service checklist.
public struct ServiceTask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var isDone: Bool = false
    public var note: String = ""

    public init(id: UUID = UUID(), title: String, isDone: Bool = false, note: String = "") {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.note = note
    }
}
