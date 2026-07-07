import SwiftUI

public struct CircularGauge: View {
    var value: Double
    var maxValue: Double
    var label: String
    var unit: String
    var color: Color

    @State private var animatedValue: Double = 0

    public init(value: Double, maxValue: Double, label: String, unit: String = "", color: Color = HUDTheme.cyan) {
        self.value = value
        self.maxValue = maxValue
        self.label = label
        self.unit = unit
        self.color = color
    }

    private var progress: Double {
        guard maxValue > 0 else { return 0 }
        return min(max(animatedValue / maxValue, 0), 1)
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .hudGlow(color, radius: 5)
                VStack(spacing: 2) {
                    Text(formattedValue)
                        .font(HUDTheme.monoFont(22, weight: .bold))
                        .foregroundStyle(HUDTheme.textPrimary)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(HUDTheme.monoFont(9))
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                }
            }
            .frame(width: 110, height: 110)

            Text(label.uppercased())
                .font(HUDTheme.monoFont(10, weight: .medium))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1.5)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) {
                animatedValue = value
            }
        }
        .onChange(of: value) { _, newValue in
            withAnimation(.easeOut(duration: 0.8)) {
                animatedValue = newValue
            }
        }
    }

    private var formattedValue: String {
        animatedValue >= 100 ? String(Int(animatedValue)) : String(format: "%.1f", animatedValue)
    }
}
