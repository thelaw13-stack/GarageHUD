import SwiftUI

public struct StatReadout: View {
    var label: String
    var value: String
    var unit: String
    var color: Color

    public init(label: String, value: String, unit: String = "", color: Color = HUDTheme.textPrimary) {
        self.label = label
        self.value = value
        self.unit = unit
        self.color = color
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(HUDTheme.monoFont(9, weight: .medium))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1.2)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(HUDTheme.monoFont(18, weight: .semibold))
                    .foregroundStyle(color)
                if !unit.isEmpty {
                    Text(unit)
                        .font(HUDTheme.monoFont(11))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
            }
        }
    }
}
