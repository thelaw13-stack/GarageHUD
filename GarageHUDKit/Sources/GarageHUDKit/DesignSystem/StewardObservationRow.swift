import SwiftUI

/// Renders one Fleet Steward observation the way the design brief asks: intelligence, not a
/// dashboard widget. The observation leads in plain language; evidence and a trust-calibrated
/// confidence label sit beneath it in restrained metadata. Severity is a single thin accent
/// bar — no glowing icons, no competing color.
public struct StewardObservationRow: View {
    private let observation: StewardObservation
    public init(_ observation: StewardObservation) { self.observation = observation }

    public var body: some View {
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            // Severity as a quiet vertical accent; routine info stays neutral.
            RoundedRectangle(cornerRadius: 1)
                .fill(accent)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: HUDTheme.space2) {
                Text(observation.statement)
                    .font(HUDTheme.body(.medium))
                    .foregroundStyle(HUDTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                metaRow("Evidence", observation.evidence)
                confidenceRow
            }
        }
        .padding(.vertical, HUDTheme.space1)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textTertiary)
                .tracking(1)
            Text(value)
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confidenceRow: some View {
        HStack(spacing: HUDTheme.space2) {
            Text("CONFIDENCE")
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textTertiary)
                .tracking(1)
            Text(observation.confidence.label)
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(confidenceColor)
            if let tag = provenanceTag {
                Text(tag.text)
                    .font(HUDTheme.monoFont(8, weight: .semibold))
                    .foregroundStyle(tag.color)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(tag.color.opacity(0.4), lineWidth: 1))
            }
        }
    }

    /// Live frames wear their honesty on their sleeve: estimated (simulated) muted, measured
    /// (real adapter) in confident cyan. Recorded/derived carry no tag.
    private var provenanceTag: (text: String, color: Color)? {
        switch observation.provenance {
        case .estimatedLive: return ("ESTIMATED", HUDTheme.textSecondary)
        case .measuredLive: return ("MEASURED", HUDTheme.cyan)
        case .recorded, .derived: return nil
        }
    }

    /// Only escalate color for things that actually need attention (brief: color = meaning).
    private var accent: Color {
        switch observation.tone {
        case .advisory: return HUDTheme.danger
        case .caution: return HUDTheme.amber
        case .informational: return HUDTheme.hairline
        }
    }

    private var confidenceColor: Color {
        switch observation.confidence {
        case .confirmed, .strong: return HUDTheme.textPrimary
        case .moderate: return HUDTheme.textSecondary
        case .weak, .insufficient: return HUDTheme.amber
        }
    }
}
