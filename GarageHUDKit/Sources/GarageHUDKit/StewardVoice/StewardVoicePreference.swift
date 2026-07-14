import Foundation

/// Chooses the best-sounding installed voice for the Steward. The default iOS voice is the low
/// quality "compact" one — the robotic sound the owner (rightly) disliked. iOS also ships far
/// better **Enhanced** and **Premium** (neural, Siri-adjacent) voices, but an app must *explicitly*
/// select one; the synthesizer never upgrades on its own. This is the pure ranking logic, kept free
/// of AVFoundation so it's unit-testable without a device.
public enum StewardVoicePreference {
    /// A voice candidate reduced to just what ranking needs.
    public struct Candidate: Equatable, Sendable {
        public let identifier: String
        public let name: String
        public let language: String   // BCP-47, e.g. "en-US"
        public let qualityRank: Int   // 3 premium, 2 enhanced, 1 default (matches AVSpeechSynthesisVoiceQuality)
        public let isNovelty: Bool    // "Bad News", "Bells", "Trinoids"… never pick these to speak plainly

        public init(identifier: String, name: String, language: String, qualityRank: Int, isNovelty: Bool = false) {
            self.identifier = identifier
            self.name = name
            self.language = language
            self.qualityRank = qualityRank
            self.isNovelty = isNovelty
        }
    }

    /// Pick the best candidate for a preferred language (e.g. "en-US"), preferring:
    /// 1. exact-language, highest quality; 2. same base language ("en"), highest quality;
    /// 3. any highest-quality non-novelty voice. Returns nil only when there are no usable voices.
    public static func best(from candidates: [Candidate], preferredLanguage: String = "en-US") -> Candidate? {
        let usable = candidates.filter { !$0.isNovelty }
        guard !usable.isEmpty else { return nil }

        let base = String(preferredLanguage.prefix(2)).lowercased()
        func rank(_ c: Candidate) -> (Int, Int, Int) {
            let exact = c.language.caseInsensitiveCompare(preferredLanguage) == .orderedSame ? 2 : 0
            let sameBase = c.language.lowercased().hasPrefix(base) ? 1 : 0
            return (exact + sameBase, c.qualityRank, 0)
        }
        // Highest (language match, quality) wins; ties broken by name for determinism.
        return usable.max { a, b in
            let ra = rank(a), rb = rank(b)
            if ra != rb { return ra < rb }
            return a.name > b.name
        }
    }

    /// True when the only thing installed for the language is a default-quality voice, so the app
    /// should nudge the owner to download an Enhanced/Premium one in Settings.
    public static func onlyDefaultAvailable(_ candidates: [Candidate], preferredLanguage: String = "en-US") -> Bool {
        let base = String(preferredLanguage.prefix(2)).lowercased()
        let inLanguage = candidates.filter { !$0.isNovelty && $0.language.lowercased().hasPrefix(base) }
        guard !inLanguage.isEmpty else { return false }
        return inLanguage.allSatisfy { $0.qualityRank <= 1 }
    }
}
