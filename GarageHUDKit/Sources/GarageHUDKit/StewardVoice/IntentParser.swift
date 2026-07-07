import Foundation

/// Represents a parsed intent extracted from a spoken utterance. At this stage
/// the intent is a simple wrapper around the original string, but future
/// expansions may introduce a richer type hierarchy reflecting different
/// commands, queries, or context. Keeping this as a struct rather than an
/// enum avoids prematurely constraining the space of possible intents.
public struct StewardIntent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    /// The raw utterance captured from speech recognition. Downstream
    /// components may use this as a fallback when no structured intent can
    /// be inferred.
    public var raw: String

    public init(id: UUID = UUID(), raw: String) {
        self.id = id
        self.raw = raw
    }
}

/// Converts a raw utterance into a `StewardIntent`. Implementations may
/// incorporate pattern matching, natural language processing, or ML models
/// depending on the sophistication required. A trivial parser could simply
/// wrap the input string in a `StewardIntent`.
public protocol IntentParser {
    func parse(_ utterance: String) -> StewardIntent
}