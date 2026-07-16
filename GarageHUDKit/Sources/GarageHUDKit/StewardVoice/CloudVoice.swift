import Foundation

/// A natural, cloud-synthesized voice for the Steward. On-device `AVSpeechSynthesizer` caps at the
/// robotic "2009" sound (Apple reserves the real Siri voice), so for a genuinely human voice we call
/// a neural TTS. Kept behind a small config + pure request builder so the networking is testable and
/// the provider is swappable; the owner supplies their own API key (stored in the Keychain), and the
/// whole thing degrades to on-device speech whenever it isn't configured or the network fails.
public enum CloudVoiceProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case openAI
    public var id: String { rawValue }
    public var displayName: String { self == .openAI ? "OpenAI" : rawValue }
    public var keychainAccount: String { "cloudVoice.\(rawValue).apiKey" }
}

/// The user-selectable voice options (OpenAI's set). "Onyx" — deep and calm — is the default that
/// fits a shop-steward tone.
public enum CloudVoiceStyle: String, CaseIterable, Codable, Sendable, Identifiable {
    case onyx, ash, sage, alloy, echo, nova, shimmer
    public var id: String { rawValue }
    public var displayName: String { rawValue.capitalized }
}

public struct CloudVoiceConfig: Equatable, Sendable {
    public var enabled: Bool
    public var provider: CloudVoiceProvider
    public var style: CloudVoiceStyle

    public init(enabled: Bool = false, provider: CloudVoiceProvider = .openAI, style: CloudVoiceStyle = .onyx) {
        self.enabled = enabled
        self.provider = provider
        self.style = style
    }

    /// Persisted preferences (not the key — that's in the Keychain).
    private static let enabledKey = "GarageHUD.cloudVoice.enabled"
    private static let providerKey = "GarageHUD.cloudVoice.provider"
    private static let styleKey = "GarageHUD.cloudVoice.style"

    public static func load(_ defaults: UserDefaults = .standard) -> CloudVoiceConfig {
        CloudVoiceConfig(
            enabled: defaults.bool(forKey: enabledKey),
            provider: defaults.string(forKey: providerKey).flatMap(CloudVoiceProvider.init) ?? .openAI,
            style: defaults.string(forKey: styleKey).flatMap(CloudVoiceStyle.init) ?? .onyx)
    }

    public func save(_ defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: Self.enabledKey)
        defaults.set(provider.rawValue, forKey: Self.providerKey)
        defaults.set(style.rawValue, forKey: Self.styleKey)
    }

    /// The key is present in the Keychain for the chosen provider.
    public var hasKey: Bool { KeychainStore.has(provider.keychainAccount) }
    /// Active only when the owner has both enabled it and supplied a key.
    public var isActive: Bool { isActive(hasKey: hasKey) }

    public func isActive(hasKey: Bool) -> Bool {
        enabled && hasKey
    }
}

public enum CloudVoiceError: Error, Equatable { case notConfigured, badResponse(Int), emptyAudio, transport }

/// Builds the HTTPS request for a provider. Pure so URL/headers/body are unit-testable without
/// hitting the network or exposing a real key.
public enum CloudVoiceRequest {
    public static func build(provider: CloudVoiceProvider, style: CloudVoiceStyle,
                             text: String, apiKey: String) -> URLRequest {
        switch provider {
        case .openAI:
            var req = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
            req.httpMethod = "POST"
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": "gpt-4o-mini-tts",
                "voice": style.rawValue,
                "input": text,
                "response_format": "mp3",
                // A calm, measured delivery — the Steward advises, it doesn't hype.
                "instructions": "Calm, measured, knowledgeable. A trusted shop steward — never salesy.",
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            req.timeoutInterval = 20
            return req
        }
    }
}

/// Fetches synthesized audio for a line of text. Returns the audio bytes (mp3) to be played by the
/// voice session. Any failure throws, so the caller can fall back to on-device speech.
public struct CloudVoiceSynthesizer: Sendable {
    public var config: CloudVoiceConfig
    public var session: URLSession
    public init(config: CloudVoiceConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func synthesize(_ text: String) async throws -> Data {
        guard config.isActive, let key = KeychainStore.get(config.provider.keychainAccount) else {
            throw CloudVoiceError.notConfigured
        }
        let request = CloudVoiceRequest.build(provider: config.provider, style: config.style, text: text, apiKey: key)
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: request) }
        catch { throw CloudVoiceError.transport }
        guard let http = response as? HTTPURLResponse else { throw CloudVoiceError.transport }
        guard (200..<300).contains(http.statusCode) else { throw CloudVoiceError.badResponse(http.statusCode) }
        guard !data.isEmpty else { throw CloudVoiceError.emptyAudio }
        return data
    }
}
