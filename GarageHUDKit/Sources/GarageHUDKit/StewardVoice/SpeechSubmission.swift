import Foundation

/// What a stop should do with what was heard.
///
/// W-062, field-found 2026-07-19: tapping the mic a second time stopped listening but never sent
/// the utterance, so one intent cost two gestures — against the standing rule that one gesture
/// gets one response. The transport reason was that the manual stop cancelled the recognition task
/// before its final result could arrive, killing the only path that submitted.
///
/// Kept pure and outside the Speech/AVFoundation guard so the rule is testable without a
/// microphone; the capture shell applies it.
public enum SpeechSubmission {

    /// The utterance to submit, or nil when there is nothing worth asking.
    ///
    /// An empty or whitespace-only transcript means the owner tapped the mic and said nothing —
    /// that is a cancel, not a question, and must not fire an empty exchange.
    public static func utteranceToSubmit(_ transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
