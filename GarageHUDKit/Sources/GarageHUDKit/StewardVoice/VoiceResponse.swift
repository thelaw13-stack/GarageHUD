import Foundation

/// A component that generates spoken or textual responses to user intents.
/// Decoupling response generation from routing allows for unit testing of
/// conversational logic and for different response strategies depending on
/// driving mode or user preference (e.g. text‑only vs. speech).
public protocol VoiceResponder {
    /// Computes a response for the given intent. The returned string should
    /// already be localized and ready to present. Asynchronous to allow for
    /// potentially expensive operations such as fetching remote data or
    /// running a language model.
    func respond(to intent: StewardIntent) async -> String
}