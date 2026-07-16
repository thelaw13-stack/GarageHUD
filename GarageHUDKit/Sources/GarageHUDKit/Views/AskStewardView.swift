import SwiftUI
#if canImport(Speech)
import Speech
#endif

/// The conversational surface. Type or talk: both routes run through the same
/// `StewardConversation` core, so the answer — and its confidence — is identical whether
/// it's read or spoken. Voice capture and TTS live in `StewardVoiceSession`; this view only
/// drives it and shows the exchange.
struct AskStewardView: View {
    let vehicle: Vehicle
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var question = ""
    @State private var reply: StewardReply?
    @State private var thinking = false
    @State private var showingVoiceSettings = false
    @State private var voiceNudgeDismissed = VoiceNudge.isDismissed()

    #if canImport(Speech)
    @StateObject private var voice: StewardVoiceSession
    #endif

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        #if canImport(Speech)
        _voice = StateObject(wrappedValue: StewardVoiceSession(vehicle: vehicle))
        #endif
    }

    // With the on-device LLM, open-ended questions land; without it, these still map to the keyword
    // core. Either way they seed a real conversation, not just canned lookups.
    private var quickAsks: [String] {
        if StewardAssistant.isLLMAvailable {
            return [
                "What's the smartest next $2k?",
                "Will my fueling keep up if I raise boost?",
                "What should I watch?",
                "Is my cost-per-hp reasonable?",
                "What's left to make this reliable?"
            ]
        }
        return ["What should I watch?", "How much power?", "What did I spend?",
                "Cost per horsepower?", "When did I last touch it?"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            #if canImport(Speech)
            if showVoiceNudge { voiceNudgeBanner }
            #endif
            replyArea
            Spacer(minLength: 0)
            quickChips
            inputBar
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDTheme.background.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        #if canImport(Speech)
        .sheet(isPresented: $showingVoiceSettings) {
            VoiceSettingsView { voice.speak($0) }
        }
        #endif
        .onAppear {
            if reply == nil { reply = StewardReply(text: "Go ahead — ask about power, spend, efficiency, or what to watch. Tap the mic to talk.") }
            #if canImport(Speech)
            voice.requestAuthorization()
            voice.onExchange = { q, r in
                question = q
                withAnimation(.easeOut(duration: 0.15)) { reply = r }
            }
            #endif
        }
        #if canImport(Speech)
        .onDisappear { voice.stop(); voice.stopSpeaking() }
        #endif
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(HUDTheme.cyan)
                Text("ASK STEWARD")
                    .font(HUDTheme.body(.bold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .tracking(1.5)
            }
            Spacer()
            #if canImport(Speech)
            if voice.isSpeaking {
                Label("speaking", systemImage: "speaker.wave.2.fill")
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.cyan)
            }
            Button { showingVoiceSettings = true } label: {
                Image(systemName: "slider.horizontal.3").foregroundStyle(HUDTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Voice settings")
            #endif
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(HUDTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var replyArea: some View {
        HUDPanel(title: vehicle.displayName) {
            VStack(alignment: .leading, spacing: 10) {
                if !question.isEmpty {
                    Text("“\(question)”")
                        .font(HUDTheme.label())
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                if thinking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Steward is thinking…")
                            .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    }
                } else {
                    Text(reply?.text ?? "")
                        .font(HUDTheme.body(.medium))
                        .foregroundStyle(HUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let confidence = reply?.confidence, !thinking {
                    Text(confidence.label)
                        .font(HUDTheme.label(.semibold))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .tracking(0.5)
                }
            }
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickAsks, id: \.self) { q in
                    Button(q) { ask(q) }.buttonStyle(.compactAction)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            #if canImport(Speech)
            micButton
            #endif
            Text("Steward…")
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.cyan)
            TextField(micPlaceholder, text: $input)
                .textFieldStyle(.plain)
                .font(HUDTheme.body())
                .onSubmit { ask(input) }
            Button { ask(input) } label: {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(HUDTheme.cyan)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(HUDTheme.panelBackground)
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.space2).strokeBorder(HUDTheme.hairline, lineWidth: 1))
    }

    private var micPlaceholder: String {
        #if canImport(Speech)
        if voice.isListening { return voice.partialTranscript.isEmpty ? "listening…" : voice.partialTranscript }
        #endif
        return "ask a question"
    }

    #if canImport(Speech)
    @ViewBuilder
    private var micButton: some View {
        Button { voice.toggle() } label: {
            Image(systemName: voice.isListening ? "waveform.circle.fill" : "mic.circle")
                .font(.system(size: 20))
                .foregroundStyle(voice.isListening ? HUDTheme.amber : HUDTheme.cyan)
                .symbolEffect(.pulse, isActive: voice.isListening)
        }
        .buttonStyle(.plain)
        .disabled(voice.authorization == .denied || voice.authorization == .unavailable)
    }
    #endif

    #if canImport(Speech)
    /// Show the "better voice" nudge only when the device has just the robotic default, the natural
    /// cloud voice is off, and it hasn't been dismissed. Re-reads the cloud setting each render, so
    /// turning cloud voice on in the sheet hides it immediately.
    private var showVoiceNudge: Bool {
        VoiceNudge.shouldShow(onlyDefaultVoiceInstalled: voice.needsBetterVoiceDownload,
                              cloudVoiceEnabled: CloudVoiceConfig.load().enabled,
                              dismissed: voiceNudgeDismissed)
    }

    private var voiceNudgeBanner: some View {
        HStack(alignment: .top, spacing: HUDTheme.space2) {
            Image(systemName: "speaker.wave.2").font(.system(size: 13)).foregroundStyle(HUDTheme.cyan).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Steward is using the basic system voice")
                    .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                Text("For a natural voice, turn one on in Voice settings — or download an enhanced voice in iOS Settings › Accessibility › Spoken Content › Voices.")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Voice settings") { showingVoiceSettings = true }
                    .buttonStyle(.compactAction).padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button {
                VoiceNudge.markDismissed(); voiceNudgeDismissed = true
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(HUDTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss voice tip")
        }
        .padding(HUDTheme.space3)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
    }
    #endif

    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !thinking else { return }
        question = q
        input = ""
        thinking = true
        Task {
            // Routes through the on-device LLM Steward when available, else the keyword core.
            let answer = await StewardAssistant.answer(question: q, vehicle: vehicle)
            thinking = false
            withAnimation(.easeOut(duration: 0.15)) { reply = answer }
            #if canImport(Speech)
            voice.speak(answer.text)
            #endif
        }
    }
}
