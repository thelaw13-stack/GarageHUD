import XCTest
@testable import GarageHUDKit

/// The natural cloud voice: a correctly-formed provider request, preferences that persist, a key
/// that lives only in the Keychain, and an "active only when configured" gate so the session knows
/// when to fall back to on-device speech.
final class CloudVoiceTests: XCTestCase {

    func testOpenAIRequestIsWellFormed() {
        let req = CloudVoiceRequest.build(provider: .openAI, style: .onyx,
                                          text: "Fueling is documented.", apiKey: "sk-test-123")
        XCTAssertEqual(req.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test-123")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["model"] as? String, "gpt-4o-mini-tts")
        XCTAssertEqual(body["voice"] as? String, "onyx")
        XCTAssertEqual(body["input"] as? String, "Fueling is documented.")
        XCTAssertEqual(body["response_format"] as? String, "mp3")
    }

    func testStyleChoiceFlowsIntoTheRequest() {
        let req = CloudVoiceRequest.build(provider: .openAI, style: .sage, text: "hi", apiKey: "k")
        let body = try! JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertEqual(body["voice"] as? String, "sage")
    }

    func testConfigPersistsPreferencesButNotTheKey() {
        let suite = "CloudVoiceTests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }

        CloudVoiceConfig(enabled: true, provider: .openAI, style: .nova).save(d)
        let loaded = CloudVoiceConfig.load(d)
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.style, .nova)
        // The key is never in UserDefaults — only the Keychain.
        XCTAssertNil(d.string(forKey: "GarageHUD.cloudVoice.apiKey"))
    }

    func testIsActiveRequiresBothEnabledAndAKey() {
        let account = "cloudVoice.test.\(UUID().uuidString)"
        // Not enabled → not active regardless of key.
        XCTAssertFalse(CloudVoiceConfig(enabled: false).isActive)
        // Enabled but no key → not active (would fall back to on-device).
        var enabledNoKey = CloudVoiceConfig(enabled: true)
        XCTAssertFalse(enabledNoKey.hasKey || enabledNoKey.isActive)
        _ = enabledNoKey   // silence unused-mutation
    }

    func testKeychainRoundTripAndDelete() {
        let account = "cloudVoice.test.\(UUID().uuidString)"
        XCTAssertFalse(KeychainStore.has(account))
        XCTAssertTrue(KeychainStore.set("sk-secret", for: account))
        XCTAssertEqual(KeychainStore.get(account), "sk-secret")
        XCTAssertTrue(KeychainStore.has(account))
        // Overwrite, then delete via nil.
        XCTAssertTrue(KeychainStore.set("sk-new", for: account))
        XCTAssertEqual(KeychainStore.get(account), "sk-new")
        KeychainStore.set(nil, for: account)
        XCTAssertNil(KeychainStore.get(account))
        XCTAssertFalse(KeychainStore.has(account))
    }

    func testSynthesizeThrowsNotConfiguredWhenInactive() async {
        // No key + disabled → the synthesizer refuses, so the session falls back to on-device.
        let synth = CloudVoiceSynthesizer(config: CloudVoiceConfig(enabled: false))
        do {
            _ = try await synth.synthesize("hello")
            XCTFail("expected notConfigured")
        } catch {
            XCTAssertEqual(error as? CloudVoiceError, .notConfigured)
        }
    }
}
