import SwiftUI

/// Where the owner turns on the natural cloud voice and supplies their own API key. The key is
/// written straight to the Keychain — never to the garage file, UserDefaults, or a log — and the
/// screen is honest that enabling this sends the Steward's spoken reply to the provider.
struct VoiceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    /// The live session, so "Test voice" speaks through the exact same path a real answer does.
    var speak: (String) -> Void

    @State private var enabled = false
    @State private var style: CloudVoiceStyle = .onyx
    @State private var keyInput = ""
    @State private var keyOnFile = false

    private let provider: CloudVoiceProvider = .openAI

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use a natural cloud voice", isOn: $enabled)
                } footer: {
                    Text("On-device speech is robotic — Apple reserves the natural Siri voice. A neural cloud voice sounds human. When it's off or offline, the Steward falls back to the on-device voice automatically.")
                }

                if enabled {
                    Section("Voice") {
                        Picker("Voice", selection: $style) {
                            ForEach(CloudVoiceStyle.allCases) { Text($0.displayName).tag($0) }
                        }
                        Button("Test voice") {
                            persist()
                            speak("This is your Steward. Fueling is documented, and the last dyno read 381 wheel horsepower.")
                        }
                        .disabled(!(keyOnFile || !keyInput.isEmpty))
                    }

                    Section {
                        SecureField(keyOnFile ? "Key saved — paste to replace" : "Paste your \(provider.displayName) API key", text: $keyInput)
                            .textContentType(.password)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            #endif
                        if keyOnFile {
                            Button("Remove saved key", role: .destructive) {
                                KeychainStore.set(nil, for: provider.keychainAccount)
                                keyOnFile = false
                                keyInput = ""
                            }
                        }
                    } header: {
                        Text("\(provider.displayName) API key")
                    } footer: {
                        Text("Stored only in your device Keychain. Get a key at platform.openai.com → API keys. Replies are short, so cost is a fraction of a cent each. Your reply text is sent to \(provider.displayName) to be spoken.")
                    }
                }
            }
            .navigationTitle("Steward Voice")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { persist(); dismiss() } }
            }
            .onAppear(perform: load)
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }

    private func load() {
        let config = CloudVoiceConfig.load()
        enabled = config.enabled
        style = config.style
        keyOnFile = config.hasKey
    }

    private func persist() {
        if !keyInput.isEmpty {
            KeychainStore.set(keyInput.trimmingCharacters(in: .whitespacesAndNewlines), for: provider.keychainAccount)
            keyOnFile = true
            keyInput = ""
        }
        CloudVoiceConfig(enabled: enabled, provider: provider, style: style).save()
    }
}
