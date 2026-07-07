import SwiftUI

struct VehicleDashboardView: View {
    var vehicle: Vehicle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                keyMetrics
                buildProgress
                nextSteps
                recentActivity
            }
            .padding(24)
        }
        .background(HUDTheme.background)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.displayName.uppercased())
                    .font(HUDTheme.monoFont(24, weight: .bold))
                    .foregroundStyle(HUDTheme.cyan)
                    .hudGlow(HUDTheme.cyan, radius: 6)
                Text(vehicle.subtitle)
                    .font(HUDTheme.monoFont(13))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            Spacer()
            if let lastActivity = vehicle.lastActivityDate {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("LAST ACTIVITY")
                        .font(HUDTheme.monoFont(8, weight: .semibold))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .tracking(1.5)
                    Text(lastActivity.formatted(date: .abbreviated, time: .omitted))
                        .font(HUDTheme.monoFont(12, weight: .medium))
                        .foregroundStyle(HUDTheme.textPrimary)
                }
            }
        }
    }

    private var keyMetrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("KEY METRICS")
                .font(HUDTheme.monoFont(11, weight: .semibold))
                .foregroundStyle(HUDTheme.cyan)
                .tracking(2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                MetricTile(
                    label: "Horsepower",
                    value: vehicle.currentHorsepowerEstimate.map { "\(Int($0))" } ?? "—",
                    unit: "HP",
                    color: HUDTheme.danger,
                    subtitle: vehicle.latestPerformance?.type == .dyno ? "Last dyno" : "Factory rated"
                )
                MetricTile(
                    label: "Torque",
                    value: (vehicle.performanceRecords.filter { $0.type == .dyno }.sorted { $0.date > $1.date }.first?.wheelTorque ?? vehicle.factoryTorque).map { "\(Int($0))" } ?? "—",
                    unit: "LB-FT",
                    color: HUDTheme.blue
                )
                if let ratio = vehicle.powerToWeight {
                    MetricTile(label: "Power/Weight", value: String(format: "%.1f", ratio), unit: "lb/hp", color: HUDTheme.purple)
                }
                if let weight = vehicle.factoryWeightLbs {
                    MetricTile(label: "Weight", value: "\(Int(weight))", unit: "lbs", color: HUDTheme.textPrimary)
                }
                MetricTile(label: "Installed Parts", value: "\(vehicle.installedPartsCount)", color: HUDTheme.cyan)
                if let latest = vehicle.latestPerformance {
                    MetricTile(label: "Latest Test", value: latest.summary, color: HUDTheme.amber, subtitle: latest.type.rawValue)
                }
            }
        }
    }

    private var buildProgress: some View {
        HUDPanel(title: "Build Progress") {
            HStack(spacing: 24) {
                CircularGauge(value: vehicle.buildCompletionPercent, maxValue: 100, label: "Complete", unit: "%", color: HUDTheme.cyan)
                VStack(alignment: .leading, spacing: 8) {
                    if !vehicle.engineDescription.isEmpty {
                        StatReadout(label: "Engine", value: vehicle.engineDescription)
                    }
                    if !vehicle.drivetrainDescription.isEmpty {
                        StatReadout(label: "Drivetrain", value: vehicle.drivetrainDescription)
                    }
                }
                Spacer()
            }
        }
    }

    private var nextSteps: some View {
        let suggestions = BuildAdvisor.suggestions(for: vehicle)
        return HUDPanel(title: "Next Steps") {
            if suggestions.isEmpty {
                Text("No gaps detected and nothing on the wishlist — add wishlist parts on the Parts tab to see them here.")
                    .font(HUDTheme.monoFont(12))
                    .foregroundStyle(HUDTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(suggestions) { suggestion in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: suggestion.isWishlistItem ? "star.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(suggestion.isWishlistItem ? HUDTheme.amber : HUDTheme.danger)
                                .padding(.top, 2)
                            Text(suggestion.text)
                                .font(HUDTheme.monoFont(11.5))
                                .foregroundStyle(HUDTheme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var recentActivity: some View {
        HUDPanel(title: "Recent Activity") {
            let events = Array(vehicle.buildEvents.sorted { $0.date > $1.date }.prefix(5))
            if events.isEmpty {
                Text("No build events logged yet.")
                    .font(HUDTheme.monoFont(12))
                    .foregroundStyle(HUDTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(events) { event in
                        HStack {
                            Circle().fill(HUDTheme.cyan).frame(width: 6, height: 6)
                            Text(event.title)
                                .font(HUDTheme.monoFont(12, weight: .medium))
                                .foregroundStyle(HUDTheme.textPrimary)
                            Spacer()
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(HUDTheme.monoFont(10))
                                .foregroundStyle(HUDTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
