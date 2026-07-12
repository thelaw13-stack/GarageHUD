import SwiftUI

/// Renders one Fleet Steward observation the way the Constitution demands: the statement
/// leads, the evidence sits right under it, and confidence is shown explicitly — never a
/// bare recommendation, never implied certainty.
public struct StewardObservationRow: View {
    private let observation: StewardObservation
    public init(_ observation: StewardObservation) { self.observation = observation }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                Text(observation.statement)
                    .font(HUDTheme.monoFont(12, weight: .medium))
                    .foregroundStyle(HUDTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(observation.evidence)
                    .font(HUDTheme.monoFont(10))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(observation.confidence.label)
                        .font(HUDTheme.monoFont(9, weight: .semibold))
                        .foregroundStyle(accent)
                        .tracking(0.5)
                    if let tag = provenanceTag {
                        Text(tag.text)
                            .font(HUDTheme.monoFont(8, weight: .semibold))
                            .foregroundStyle(tag.color)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .overlay(Capsule().strokeBorder(tag.color.opacity(0.5), lineWidth: 1))
                    }
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Live frames wear their honesty on their sleeve: estimated (simulated) reads muted,
    /// measured (real adapter) reads in the confident cyan. Recorded/derived carry no tag.
    private var provenanceTag: (text: String, color: Color)? {
        switch observation.provenance {
        case .estimatedLive: return ("ESTIMATED", HUDTheme.textSecondary)
        case .measuredLive: return ("MEASURED", HUDTheme.cyan)
        case .recorded, .derived: return nil
        }
    }

    private var icon: String {
        switch observation.tone {
        case .advisory: "exclamationmark.triangle.fill"
        case .caution: "eye.trianglebadge.exclamationmark"
        case .informational: "sparkle.magnifyingglass"
        }
    }

    private var accent: Color {
        switch observation.tone {
        case .advisory: HUDTheme.danger
        case .caution: HUDTheme.amber
        case .informational: HUDTheme.cyan
        }
    }
}
