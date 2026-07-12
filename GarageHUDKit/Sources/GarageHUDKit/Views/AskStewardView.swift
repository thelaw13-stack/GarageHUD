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

    #if canImport(Speech)
    @StateObject private var voice: StewardVoiceSession
    #endif

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        #if canImport(Speech)
        _voice = StateObject(wrappedValue: StewardVoiceSession(vehicle: vehicle))
        #endif
    }

    private let quickAsks = [
        "What should I watch?",
        "How much power?",
        "What did I spend?",
        "Cost per horsepower?",
        "When did I last touch it?"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
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
                    .font(HUDTheme.monoFont(13, weight: .bold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(1.5)
            }
            Spacer()
            #if canImport(Speech)
            if voice.isSpeaking {
                Label("speaking", systemImage: "speaker.wave.2.fill")
                    .font(HUDTheme.monoFont(9, weight: .semibold))
                    .foregroundStyle(HUDTheme.cyan)
            }
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
                        .font(HUDTheme.monoFont(11))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                Text(reply?.text ?? "")
                    .font(HUDTheme.monoFont(15, weight: .medium))
                    .foregroundStyle(HUDTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let confidence = reply?.confidence {
                    Text(confidence.label)
                        .font(HUDTheme.monoFont(9, weight: .semibold))
                        .foregroundStyle(HUDTheme.cyan)
                        .tracking(0.5)
                }
            }
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickAsks, id: \.self) { q in
                    Button { ask(q) } label: {
                        Text(q)
                            .font(HUDTheme.monoFont(10, weight: .medium))
                            .foregroundStyle(HUDTheme.cyan)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(HUDTheme.cyan.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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
                .font(HUDTheme.monoFont(11, weight: .semibold))
                .foregroundStyle(HUDTheme.cyan)
            TextField(micPlaceholder, text: $input)
                .textFieldStyle(.plain)
                .font(HUDTheme.monoFont(13))
                .onSubmit { ask(input) }
            Button { ask(input) } label: {
                Image(systemName: "arrow.up.circle.fill").foregroundStyle(HUDTheme.cyan)
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
        .background(HUDTheme.panelBackground)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.3), lineWidth: 1))
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

    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        question = q
        let answer = StewardConversation.reply(to: q, vehicle: vehicle)
        withAnimation(.easeOut(duration: 0.15)) { reply = answer }
        input = ""
        #if canImport(Speech)
        voice.speak(answer.text)
        #endif
    }
}
