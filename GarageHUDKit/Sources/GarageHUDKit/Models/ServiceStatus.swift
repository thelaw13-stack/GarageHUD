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

    public init(isInService: Bool = false, reason: String = "", since: Date? = nil) {
        self.isInService = isInService
        self.reason = reason
        self.since = since
    }

    public static var operational: ServiceStatus { ServiceStatus() }
}
