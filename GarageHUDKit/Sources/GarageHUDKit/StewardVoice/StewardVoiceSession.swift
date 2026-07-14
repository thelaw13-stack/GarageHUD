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

    /// The vehicle Steward answers about, or nil for a fleet-level session that only *speaks*
    /// a prebuilt script (e.g. the garage briefing) and never needs a single-car context.
    /// Both are mutable so a view can keep them in sync with the app.
    public var vehicle: Vehicle?
    public var mode: DrivingMode

    /// Fired on the main actor after a final utterance is recognized and answered, so the
    /// UI can show the exchange as text alongside the spoken reply.
    public var onExchange: ((_ question: String, _ reply: StewardReply) -> Void)?

    private let recognizer = SFSpeechRecognizer()
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()

    /// The chosen high-quality voice, resolved once. Nil falls back to the system default.
    private lazy var preferredVoice: AVSpeechSynthesisVoice? = Self.resolvePreferredVoice()
    /// Cloud-TTS playback + a token so a newer spoken line supersedes an in-flight one.
    private var cloudPlayer: AVAudioPlayer?
    private var cloudSpeakToken = 0
    /// The display name of the voice being used, and whether only a low-quality one is installed —
    /// so the UI can name the voice and, when needed, nudge the owner to download a better one.
    @Published public private(set) var voiceName: String = ""
    @Published public private(set) var needsBetterVoiceDownload = false

    public init(vehicle: Vehicle?, mode: DrivingMode = .parked) {
        self.vehicle = vehicle
        self.mode = mode
        super.init()
        synthesizer.delegate = self
        voiceName = preferredVoice?.name ?? "System default"
        needsBetterVoiceDownload = Self.onlyDefaultVoiceInstalled()
    }

    // MARK: Voice selection

    private static func candidates() -> [StewardVoicePreference.Candidate] {
        AVSpeechSynthesisVoice.speechVoices().map { v in
            StewardVoicePreference.Candidate(
                identifier: v.identifier, name: v.name, language: v.language,
                qualityRank: v.quality.rank,
                // Novelty voices carry a distinctive identifier segment and shouldn't narrate.
                isNovelty: v.identifier.contains(".custom") || Self.noveltyNames.contains(v.name))
        }
    }

    private static let noveltyNames: Set<String> = [
        "Albert", "Bad News", "Bahh", "Bells", "Boing", "Bubbles", "Cellos", "Wobble",
        "Good News", "Jester", "Organ", "Superstar", "Trinoids", "Whisper", "Zarvox"
    ]

    private static func resolvePreferredVoice() -> AVSpeechSynthesisVoice? {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        guard let best = StewardVoicePreference.best(from: candidates(), preferredLanguage: lang) else { return nil }
        return AVSpeechSynthesisVoice(identifier: best.identifier)
    }

    private static func onlyDefaultVoiceInstalled() -> Bool {
        StewardVoicePreference.onlyDefaultAvailable(candidates(),
                                                    preferredLanguage: AVSpeechSynthesisVoice.currentLanguageCode())
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
        // A fleet-level session (no single-car context) doesn't field free-form questions —
        // it only speaks prebuilt scripts like the briefing.
        guard let vehicle else { return }
        // Route spoken questions through the same assistant as typed ones: on-device LLM when
        // available, keyword core otherwise.
        Task { @MainActor in
            let reply = await StewardAssistant.answer(question: trimmed, vehicle: vehicle, mode: mode)
            onExchange?(trimmed, reply)
            speak(reply.text)
        }
    }

    // MARK: Speak

    public func speak(_ text: String) {
        guard !text.isEmpty else { return }
        // Prefer the natural cloud voice when the owner has configured it; fall back to on-device
        // speech if it isn't active or the request fails (offline, bad key, provider error).
        let config = CloudVoiceConfig.load()
        guard config.isActive else { speakOnDevice(text); return }
        cloudSpeakToken += 1
        let token = cloudSpeakToken
        Task { [weak self] in
            do {
                let audio = try await CloudVoiceSynthesizer(config: config).synthesize(text)
                guard let self, token == self.cloudSpeakToken else { return }   // superseded by a newer line
                self.playCloudAudio(audio, fallbackText: text)
            } catch {
                guard let self, token == self.cloudSpeakToken else { return }
                self.speakOnDevice(text)   // graceful fallback — the owner still hears the answer
            }
        }
    }

    private func speakOnDevice(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        // Use the best installed voice (Premium/Enhanced neural), not the robotic compact default.
        utterance.voice = preferredVoice
        // Calm and a touch measured — Steward advises, it doesn't chatter. A hair below default rate
        // and just under natural pitch reads as considered rather than clipped.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * (mode == .moving ? 0.94 : 0.97)
        utterance.pitchMultiplier = 0.98
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    private func playCloudAudio(_ data: Data, fallbackText: String) {
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            cloudPlayer = player
            isSpeaking = true
            player.play()
        } catch {
            speakOnDevice(fallbackText)
        }
    }

    public func stopSpeaking() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        cloudSpeakToken += 1
        cloudPlayer?.stop()
        cloudPlayer = nil
        isSpeaking = false
    }
}

extension StewardVoiceSession: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.cloudPlayer = nil
            self.isSpeaking = false
        }
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    /// 1 default / 2 enhanced / 3 premium — the enum's own rawValue, named for intent.
    var rank: Int { rawValue }
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
