import XCTest
@testable import GarageHUDKit

/// The Steward must pick the best installed voice, not the robotic compact default the owner
/// disliked. This tests the pure ranking (Premium > Enhanced > default, right language, no novelty).
final class StewardVoicePreferenceTests: XCTestCase {
    typealias C = StewardVoicePreference.Candidate

    func testPrefersPremiumOverEnhancedOverDefault() {
        let voices = [
            C(identifier: "def", name: "Samantha", language: "en-US", qualityRank: 1),
            C(identifier: "enh", name: "Evan", language: "en-US", qualityRank: 2),
            C(identifier: "prem", name: "Zoe", language: "en-US", qualityRank: 3),
        ]
        XCTAssertEqual(StewardVoicePreference.best(from: voices)?.identifier, "prem")
    }

    func testPrefersExactLanguageThenSameBase() {
        let voices = [
            C(identifier: "gb-prem", name: "Daniel", language: "en-GB", qualityRank: 3),
            C(identifier: "us-enh", name: "Evan", language: "en-US", qualityRank: 2),
        ]
        // Exact en-US match wins even though the en-GB voice is higher quality.
        XCTAssertEqual(StewardVoicePreference.best(from: voices, preferredLanguage: "en-US")?.identifier, "us-enh")
    }

    func testFallsBackToSameBaseLanguageWhenNoExactMatch() {
        let voices = [
            C(identifier: "gb", name: "Daniel", language: "en-GB", qualityRank: 3),
            C(identifier: "fr", name: "Thomas", language: "fr-FR", qualityRank: 3),
        ]
        XCTAssertEqual(StewardVoicePreference.best(from: voices, preferredLanguage: "en-US")?.identifier, "gb")
    }

    func testNeverPicksNoveltyVoices() {
        let voices = [
            C(identifier: "novelty", name: "Trinoids", language: "en-US", qualityRank: 3, isNovelty: true),
            C(identifier: "real", name: "Samantha", language: "en-US", qualityRank: 1),
        ]
        XCTAssertEqual(StewardVoicePreference.best(from: voices)?.identifier, "real")
    }

    func testDetectsWhenOnlyDefaultQualityIsInstalled() {
        let onlyDefault = [C(identifier: "d", name: "Samantha", language: "en-US", qualityRank: 1)]
        XCTAssertTrue(StewardVoicePreference.onlyDefaultAvailable(onlyDefault))

        let hasEnhanced = [
            C(identifier: "d", name: "Samantha", language: "en-US", qualityRank: 1),
            C(identifier: "e", name: "Evan", language: "en-US", qualityRank: 2),
        ]
        XCTAssertFalse(StewardVoicePreference.onlyDefaultAvailable(hasEnhanced))
    }

    func testNilWhenNoUsableVoices() {
        XCTAssertNil(StewardVoicePreference.best(from: []))
        let onlyNovelty = [C(identifier: "n", name: "Bells", language: "en-US", qualityRank: 3, isNovelty: true)]
        XCTAssertNil(StewardVoicePreference.best(from: onlyNovelty))
    }
}
