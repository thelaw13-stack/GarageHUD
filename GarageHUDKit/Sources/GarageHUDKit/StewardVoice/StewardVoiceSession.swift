import Foundation

#if canImport(Speech) && canImport(AVFoundation)
import Speech
import AVFoundation

/// The live voice loop: microphone → on-device recognition → the (already proven)
/// `StewardConversation` core → spoken reply. Nothing about *what* Steward says lives
/// here — this is only capture and speech. That's deliberate: the conversation logic
/// stayed pure and testable in Sprint B, and this shell wraps it without duplicating a
/// word of it.
///
/// Driving mode flows straight through to the core, so a moving-vehicle answer is already
/// shortened before it is ever spoken.
@MainActor
public final class StewardVoiceSession: NSObject, ObservableObject {

    // Observable state for the UI.
    @Published public private(set) var isListening = false
    @Published public private(set) var isSpeaking = false
    @Published public private(set) var partialTranscript = ""
    @Published public private(set) var authorization: SpeechAuthorization = .undetermined

    public enum SpeechAuthorization: Equatable, Sendable {
        case undetermined, authorized, denied, unavailable
    }

    /// The vehicle Steward answers about, and the current context. Both are mutable so a
    /// view can keep them in sync with the app.
    public var vehicle: Vehicle
    public var mode: DrivingMode

    /// Fired on the main actor after a final utterance is recognized and answered, so the
    /// UI can show the exchange as text alongside the spoken reply.
    public var onExchange: ((_ question: String, _ reply: StewardReply) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    public init(vehicle: Vehicle, mode: DrivingMode = .parked) {
        self.vehicle = vehicle
        self.mode = mode
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Authorization

    /// Asks for speech-recognition permission. Microphone permission is requested lazily by
    /// the audio engine on first `start()`. Safe to call repeatedly.
    public func requestAuthorization() {
        guard recognizer != nil else { authorization = .unavailable; return }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                switch status {
                case .authorized: self?.authorization = .authorized
                case .denied, .restricted: self?.authorization = .denied
                case .notDetermined: self?.authorization = .undetermined
                @unknown default: self?.authorization = .denied
                }
            }
        }
    }

    // MARK: Listen

    public func toggle() { isListening ? stop() : start() }

    public func start() {
        guard !isListening, let recognizer, recognizer.isAvailable else { return }
        stopSpeaking()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            authorization = .unavailable
            return
        }
        #endif

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do { try audioEngine.start() } catch { cleanupAudio(); return }
        isListening = true
        partialTranscript = ""

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    if result.isFinal { self.finish(with: self.partialTranscript) }
                }
                if error != nil { self.stop() }
            }
        }
    }

    public func stop() {
        guard isListening else { return }
        request?.endAudio()
        cleanupAudio()
        task?.cancel()
        task = nil
        request = nil
        isListening = false
    }

    private func cleanupAudio() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func finish(with utterance: String) {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        stop()
        guard !trimmed.isEmpty else { return }
        let reply = StewardConversation.reply(to: trimmed, vehicle: vehicle, mode: mode)
        onExchange?(trimmed, reply)
        speak(reply.text)
    }

    // MARK: Speak

    public func speak(_ text: String) {
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        // Calm and a touch measured — Steward advises, it doesn't chatter.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (mode == .moving ? 0.96 : 1.0)
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    public func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }
}

extension StewardVoiceSession: AVSpeechSynthesizerDelegate {
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    public nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

#endif
