import Foundation

/// Captures spoken input and produces recognized transcripts as an async
/// sequence. This protocol abstracts over whichever speech recognition
/// framework is available on the current platform. Conformers should expose
/// recognized utterances via the `transcripts` stream and manage start/stop
/// internally. A basic implementation could wrap `SFSpeechRecognizer` on iOS
/// and `NSSpeechRecognizer` on macOS.
public protocol SpeechInput: AnyObject {
    /// A stream of recognized utterances. New strings are yielded as they
    /// become available. Implementations should finish the stream when
    /// recognition is stopped permanently.
    var transcripts: AsyncStream<String> { get }

    /// Begins capturing audio and producing transcripts. Calling this method
    /// multiple times without an intervening `stop()` should be idempotent.
    func start()

    /// Stops capturing audio and terminates the transcripts stream. Once
    /// stopped the recognizer cannot be restarted; create a new instance to
    /// begin a fresh session.
    func stop()
}