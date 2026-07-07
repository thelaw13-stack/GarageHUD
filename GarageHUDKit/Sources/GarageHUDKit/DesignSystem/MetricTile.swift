import SwiftUI

/// A dense, bordered stat card — big colored number, unit, optional subtitle.
/// Reads better at a glance than a circular gauge for peak/summary values.
public struct MetricTile: View {
    var label: String
    var value: String
    var unit: String
    var color: Color
    var subtitle: String?

    public init(label: String, value: String, unit: String = "", color: Color = HUDTheme.textPrimary, subtitle: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
        self.color = color
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(HUDTheme.monoFont(9, weight: .semibold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(HUDTheme.monoFont(26, weight: .bold))
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(HUDTheme.monoFont(11, weight: .medium))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
            }
            if let subtitle {
                Text(subtitle)
                    .font(HUDTheme.monoFont(9))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.35), lineWidth: 1))
    }
}
