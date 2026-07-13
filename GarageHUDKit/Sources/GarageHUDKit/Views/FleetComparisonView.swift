import SwiftUI

/// Cross-fleet comparison: every vehicle as a column, key metrics as rows, so the whole garage
/// reads side by side. Value per metric is highlighted (the strongest number in its row is called
/// out) to make the fleet's standouts obvious at a glance. Read-only — tapping a vehicle's header
/// jumps to it.
struct FleetComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let vehicles: [Vehicle]
    var onSelect: (UUID) -> Void

    // Ordered by garage slot so the columns match the garage grid.
    private var ordered: [Vehicle] { vehicles.sorted { $0.garageSlot < $1.garageSlot } }

    var body: some View {
        NavigationStack {
            Group {
                if ordered.count < 2 {
                    emptyState
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Grid(alignment: .leading, horizontalSpacing: HUDTheme.space3, verticalSpacing: 0) {
                            headerRow
                            Divider().overlay(HUDTheme.hairline).gridCellColumns(ordered.count + 1)
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                metricRow(row)
                            }
                        }
                        .padding(HUDTheme.space4)
                    }
                }
            }
            .background(HUDTheme.background)
            .navigationTitle("Compare Fleet")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 420)
        #endif
    }

    // MARK: Rows

    private struct Row {
        let label: String
        /// Formatted value per vehicle (nil = no data, shown as em dash).
        let values: [String?]
        /// Index of the vehicle that "wins" this row, if any, to highlight.
        let bestIndex: Int?
    }

    private var rows: [Row] {
        [
            numericRow("POWER", unit: "whp", { $0.currentHorsepowerEstimate }, format: { "\(Int($0))" }),
            numericRow("ODOMETER", unit: "mi", { $0.currentMileage.map(Double.init) },
                       format: { Int($0).formatted(.number.grouping(.automatic)) }, higherIsBetter: false),
            numericRow("INVESTED", unit: "", { $0.totalInvested > 0 ? $0.totalInvested : nil },
                       format: { $0.formatted(.currency(code: "USD").precision(.fractionLength(0))) },
                       higherIsBetter: false),
            numericRow("PARTS", unit: "", { Double($0.parts.count) }, format: { "\(Int($0))" }),
            Row(label: "STATUS",
                values: ordered.map { $0.serviceStatus.isInService ? "Out of service" : "In service" },
                bestIndex: nil),
        ]
    }

    private func numericRow(_ label: String, unit: String, _ value: (Vehicle) -> Double?,
                            format: (Double) -> String, higherIsBetter: Bool = true) -> Row {
        let raw = ordered.map(value)
        let present = raw.enumerated().compactMap { i, v in v.map { (i, $0) } }
        let best = higherIsBetter ? present.max { $0.1 < $1.1 } : present.min { $0.1 < $1.1 }
        return Row(
            label: unit.isEmpty ? label : "\(label) (\(unit))",
            values: raw.map { v in v.map(format) },
            bestIndex: present.count > 1 ? best?.0 : nil)   // only highlight when there's a contest
    }

    // MARK: Cells

    private var headerRow: some View {
        GridRow {
            Text("").gridColumnAlignment(.leading)
            ForEach(ordered) { v in
                Button { dismiss(); onSelect(v.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.displayName.uppercased())
                            .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                        Text(v.subtitle).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    }
                    .frame(minWidth: 96, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, HUDTheme.space2)
    }

    @ViewBuilder
    private func metricRow(_ row: Row) -> some View {
        GridRow {
            Text(row.label)
                .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary).tracking(1)
                .gridColumnAlignment(.leading)
            ForEach(Array(row.values.enumerated()), id: \.offset) { i, value in
                let isBest = row.bestIndex == i
                Text(value ?? "—")
                    .font(HUDTheme.body(isBest ? .semibold : .regular))
                    .foregroundStyle(value == nil ? HUDTheme.textTertiary
                                     : (isBest ? HUDTheme.green : HUDTheme.textPrimary))
                    .frame(minWidth: 96, alignment: .leading)
            }
        }
        .padding(.vertical, HUDTheme.space2)
    }

    private var emptyState: some View {
        VStack(spacing: HUDTheme.space2) {
            Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundStyle(HUDTheme.textTertiary)
            Text("Add a second vehicle to compare your fleet.")
                .font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
