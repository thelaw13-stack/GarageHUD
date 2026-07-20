import Foundation

/// The conversational Steward, powered by Apple's on-device Foundation Models (Apple Intelligence).
/// It answers free-form questions about a car, grounded in that car's actual record and constrained
/// by the Steward's honesty rules (see `StewardGrounding.instructions`) — so it converses naturally
/// without fabricating horsepower or history. Entirely on-device: private, offline, no API cost.
///
/// Availability is gated three ways so the app degrades gracefully to the keyword
/// `StewardConversation` on older OSes/devices:
///   • compile-time: `#if canImport(FoundationModels)` (Xcode with the iOS 26 SDK),
///   • OS: `@available(iOS 26, macOS 26, …)`,
///   • runtime: `SystemLanguageModel` reports availability (device supports Apple Intelligence and
///     it's enabled). `StewardAssistant.isLLMAvailable` folds all three into one check for callers.
public enum StewardLLMOutcome: Sendable {
    case answered(StewardReply)
    case unavailable            // no on-device model — caller should fall back to the keyword engine
    case failed(String)         // model present but the request errored
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
enum StewardLLM {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func answer(question: String, vehicle: Vehicle, context: StewardContext = .live) async -> StewardLLMOutcome {
        guard isAvailable else { return .unavailable }
        let session = LanguageModelSession(instructions: StewardGrounding.instructions)
        let prompt = StewardGrounding.prompt(question: question, vehicle: vehicle, context: context)
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .failed("empty response") }
            // `confidence` is deliberately nil, so no evidence chip renders for an LLM answer while
            // the keyword core still shows one. Ruled 2026-07-19 rather than left as an oversight:
            // an LLM answer can lean on a measured dyno figure and a weak estimate in the same
            // paragraph, and stamping a single band across all of it would assert a confidence the
            // answer does not uniformly have — a small lie in an app built not to tell them. The
            // bands still reach the model in the record itself ("[Strong evidence]", "[Weak —
            // estimate only]") and it is instructed to respect them, so band honesty lives in the
            // prose. If a chip is ever wanted here, it needs per-claim bands, not one for the whole
            // reply.
            return .answered(StewardReply(text: text))
        } catch {
            return .failed(String(describing: error))
        }
    }
}
#endif

/// The single entry point the UI uses. Tries the on-device LLM when it's genuinely available;
/// otherwise (older OS, unsupported device, or a model error) falls back to the deterministic
/// keyword Steward so the owner always gets a grounded answer.
public enum StewardAssistant {
    /// Whether the richer conversational Steward can run right now.
    public static var isLLMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) { return StewardLLM.isAvailable }
        #endif
        return false
    }

    /// Answer a free-form question. Uses the LLM when available, else the keyword core. Always
    /// returns a reply — never leaves the owner with nothing.
    public static func answer(question: String, vehicle: Vehicle, mode: DrivingMode = .parked,
                              context: StewardContext = .live) async -> StewardReply {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            switch await StewardLLM.answer(question: question, vehicle: vehicle, context: context) {
            case .answered(let reply):
                return StewardReply(text: StewardConversation.shape(reply.text, mode: mode), confidence: reply.confidence)
            case .unavailable, .failed:
                break   // fall through to the deterministic core
            }
        }
        #endif
        return StewardConversation.reply(to: question, vehicle: vehicle, mode: mode, context: context)
    }
}
