import SwiftUI

/// The text-first conversational surface. Speaks in Steward's evidence-first voice and
/// shows confidence when an answer rests on a derived figure. Voice capture wraps this
/// later — the answers are already computed here.
struct AskStewardView: View {
    let vehicle: Vehicle
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @State private var question = ""
    @State private var reply: StewardReply?

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
        .onAppear { if reply == nil { reply = StewardReply(text: "Go ahead — ask about power, spend, efficiency, or what to watch.") } }
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
                    Text("CONFIDENCE \(confidence)%")
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
            Text("Steward…")
                .font(HUDTheme.monoFont(11, weight: .semibold))
                .foregroundStyle(HUDTheme.cyan)
            TextField("ask a question", text: $input)
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

    private func ask(_ text: String) {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        question = q
        withAnimation(.easeOut(duration: 0.15)) {
            reply = StewardConversation.reply(to: q, vehicle: vehicle)
        }
        input = ""
    }
}
