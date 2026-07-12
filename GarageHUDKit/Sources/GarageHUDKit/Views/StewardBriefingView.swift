import SwiftUI
#if canImport(Speech)
import Speech
#endif

/// The garage briefing surface — the top observations across the whole fleet, read on screen
/// and, on demand, spoken aloud. Same reasoning core as everywhere; this is just the rollup.
struct StewardBriefingView: View {
    let vehicles: [Vehicle]
    /// The safety context. The briefing drops non-advisory noise while `.moving`; callers pass
    /// the live session's mode. (Motion is not inferred here — that needs an explicit,
    /// hysteresis-guarded policy, which is out of this view's scope.)
    let drivingMode: DrivingMode
    @Environment(\.dismiss) private var dismiss

    #if canImport(Speech)
    @StateObject private var voice: StewardVoiceSession
    #endif

    init(vehicles: [Vehicle], drivingMode: DrivingMode = .parked) {
        self.vehicles = vehicles
        self.drivingMode = drivingMode
        #if canImport(Speech)
        // Fleet-level session: no fabricated vehicle — it only speaks the prebuilt script.
        _voice = StateObject(wrappedValue: StewardVoiceSession(vehicle: nil))
        #endif
    }

    private var briefing: StewardBriefing { StewardBriefingBuilder.build(for: vehicles, mode: drivingMode) }

    var body: some View {
        let brief = briefing
        VStack(alignment: .leading, spacing: 16) {
            header(brief)
            if brief.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(brief.items) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = item.vehicleName {
                                    Text(name.uppercased())
                                        .font(HUDTheme.monoFont(9, weight: .semibold))
                                        .foregroundStyle(HUDTheme.cyan.opacity(0.8))
                                        .tracking(1)
                                } else {
                                    Text("FLEET")
                                        .font(HUDTheme.monoFont(9, weight: .semibold))
                                        .foregroundStyle(HUDTheme.amber.opacity(0.9))
                                        .tracking(1)
                                }
                                StewardObservationRow(item.observation)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            playBar(brief)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDTheme.background.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
        #if canImport(Speech)
        .onDisappear { voice.stopSpeaking() }
        #endif
    }

    private func header(_ brief: StewardBriefing) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("GARAGE BRIEFING")
                    .font(HUDTheme.monoFont(13, weight: .bold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(1.5)
                Text(brief.headline)
                    .font(HUDTheme.monoFont(11))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(HUDTheme.textSecondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30))
                .foregroundStyle(HUDTheme.cyan.opacity(0.7))
            Text("Nothing pressing across the garage. Steward is watching.")
                .font(HUDTheme.monoFont(12))
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    @ViewBuilder
    private func playBar(_ brief: StewardBriefing) -> some View {
        #if canImport(Speech)
        Button { voice.isSpeaking ? voice.stopSpeaking() : voice.speak(brief.spokenScript) } label: {
            HStack(spacing: 8) {
                Image(systemName: voice.isSpeaking ? "stop.fill" : "play.fill")
                Text(voice.isSpeaking ? "STOP" : "READ IT TO ME")
                    .font(HUDTheme.monoFont(11, weight: .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(HUDTheme.cyan)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(brief.items.isEmpty)
        #else
        EmptyView()
        #endif
    }
}
