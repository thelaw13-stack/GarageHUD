import Foundation

/// A high‑level recommendation produced by Steward. Recommendations are
/// deliberately simple structures so they can be passed between subsystems,
/// displayed in UI, or serialized for offline review. In the future they may
/// include additional metadata such as confidence intervals, supporting
/// evidence, or provenance identifiers.
public struct Recommendation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    /// Human‑readable description of the recommended action.
    public var text: String
    /// Confidence in the recommendation expressed as a fraction between 0 and 1.
    /// A `nil` value indicates that the recommendation does not carry a
    /// quantifiable confidence (e.g. wishlist item).
    public var confidence: Double?

    public init(id: UUID = UUID(), text: String, confidence: Double? = nil) {
        self.id = id
        self.text = text
        self.confidence = confidence
    }
}