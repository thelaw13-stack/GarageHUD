import SwiftUI
import Charts

struct PowerTrendChart: View {
    var records: [PerformanceRecord]

    private struct DynoPoint: Identifiable {
        let id = UUID()
        let date: Date
        let whp: Double
        let wtq: Double?
    }

    private var points: [DynoPoint] {
        records
            .filter { $0.type == .dyno && $0.wheelHorsepower != nil }
            .sorted { $0.date < $1.date }
            .map { DynoPoint(date: $0.date, whp: $0.wheelHorsepower!, wtq: $0.wheelTorque) }
    }

    var body: some View {
        // A single pull is just a lone dot — the trend only means anything with 2+ points.
        if points.count >= 2 {
            HUDPanel(title: "Power Progression") {
                Chart(points) { point in
                    LineMark(x: .value("Date", point.date), y: .value("WHP", point.whp))
                        .foregroundStyle(HUDTheme.danger)
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("Date", point.date), y: .value("WHP", point.whp))
                        .foregroundStyle(HUDTheme.danger)
                        .annotation(position: .top) {
                            Text("\(Int(point.whp)) hp")
                                .font(HUDTheme.monoFont(9, weight: .semibold))
                                .foregroundStyle(HUDTheme.danger)
                        }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(HUDTheme.textSecondary.opacity(0.2))
                        AxisValueLabel().foregroundStyle(HUDTheme.textSecondary)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine().foregroundStyle(HUDTheme.textSecondary.opacity(0.2))
                        AxisValueLabel().foregroundStyle(HUDTheme.textSecondary)
                    }
                }
                .frame(height: 180)
            }
        }
    }
}
