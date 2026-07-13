import SwiftUI

struct PerformanceView: View {
    @Binding var vehicle: Vehicle
    @State private var showingAdd = false
    @State private var editingRecord: PerformanceRecord?
    @State private var typeFilter: PerformanceType?

    private var allRecords: [PerformanceRecord] {
        vehicle.performanceRecords.sorted { $0.date > $1.date }
    }

    private var records: [PerformanceRecord] {
        guard let typeFilter else { return allRecords }
        return allRecords.filter { $0.type == typeFilter }
    }

    private var presentTypes: [PerformanceType] {
        PerformanceType.allCases.filter { type in vehicle.performanceRecords.contains { $0.type == type } }
    }

    // Personal records (best per discipline)
    private var bestDyno: PerformanceRecord? {
        vehicle.performanceRecords.filter { $0.type == .dyno && $0.wheelHorsepower != nil }
            .max { ($0.wheelHorsepower ?? 0) < ($1.wheelHorsepower ?? 0) }
    }
    private var bestQuarter: PerformanceRecord? {
        vehicle.performanceRecords.filter { $0.type == .quarterMile && $0.elapsedTimeSeconds != nil }
            .min { ($0.elapsedTimeSeconds ?? .infinity) < ($1.elapsedTimeSeconds ?? .infinity) }
    }
    private var bestSixty: PerformanceRecord? {
        vehicle.performanceRecords.filter { $0.type == .zeroToSixty && $0.elapsedTimeSeconds != nil }
            .min { ($0.elapsedTimeSeconds ?? .infinity) < ($1.elapsedTimeSeconds ?? .infinity) }
    }
    private var bestLap: PerformanceRecord? {
        vehicle.performanceRecords.filter { $0.type == .lapTime && $0.lapTimeSeconds != nil }
            .min { ($0.lapTimeSeconds ?? .infinity) < ($1.lapTimeSeconds ?? .infinity) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vehicle.performanceRecords.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        personalRecords
                        PowerTrendChart(records: allRecords)
                        typeFilterBar
                        recordGrid
                    }
                    .padding()
                }
            }
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAdd) {
            AddEditPerformanceRecordView(vehicle: $vehicle, recordID: nil)
        }
        .sheet(item: $editingRecord) { record in
            AddEditPerformanceRecordView(vehicle: $vehicle, recordID: record.id)
        }
    }

    private var header: some View {
        HStack {
            Text("PERFORMANCE")
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(2)
            Spacer()
            Button {
                showingAdd = true
            } label: {
                Label("Add Record", systemImage: "plus")
            }
            .buttonStyle(.primaryAction)
        }
        .padding()
    }

    // MARK: Personal records (hero strip)

    private var personalRecords: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
            if let dyno = bestDyno, let hp = dyno.wheelHorsepower {
                heroTile(
                    "PEAK POWER",
                    value: "\(Int(hp))",
                    unit: "whp",
                    secondary: dyno.wheelTorque.map { "\(Int($0)) lb-ft" },
                    color: HUDTheme.danger
                )
            }
            if let q = bestQuarter, let et = q.elapsedTimeSeconds {
                heroTile(
                    "BEST 1/4 MILE",
                    value: String(format: "%.2f", et),
                    unit: "sec",
                    secondary: q.trapSpeedMph.map { String(format: "%.0f mph trap", $0) },
                    color: HUDTheme.cyan
                )
            }
            if let s = bestSixty, let et = s.elapsedTimeSeconds {
                heroTile("BEST 0-60", value: String(format: "%.2f", et), unit: "sec", secondary: nil, color: HUDTheme.amber)
            }
            if let l = bestLap, let lap = l.lapTimeSeconds {
                heroTile("BEST LAP", value: String(format: "%.2f", lap), unit: "sec", secondary: l.location.isEmpty ? nil : l.location, color: HUDTheme.green)
            }
        }
    }

    private func heroTile(_ label: String, value: String, unit: String, secondary: String?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1.5)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(HUDTheme.title(.bold))
                    .foregroundStyle(color)
                Text(unit)
                    .font(HUDTheme.body())
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            Text(secondary ?? " ")
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: Filter

    private var typeFilterBar: some View {
        HStack(spacing: 8) {
            filterChip("All", isSelected: typeFilter == nil) { typeFilter = nil }
            ForEach(presentTypes) { type in
                filterChip(type.rawValue, isSelected: typeFilter == type) { typeFilter = type }
            }
            Spacer()
        }
    }

    private func filterChip(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(HUDTheme.label(.medium))
                .foregroundStyle(isSelected ? HUDTheme.background : HUDTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? HUDTheme.cyan : Color.clear))
                .overlay(Capsule().strokeBorder(HUDTheme.cyan.opacity(isSelected ? 0 : 0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Record list

    private var recordGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
            ForEach(records) { record in
                RecordCard(record: record, isPersonalBest: isPersonalBest(record))
                    .contentShape(Rectangle())
                    .onTapGesture { editingRecord = record }
                    .contextMenu {
                        Button("Edit") { editingRecord = record }
                        Button("Delete", role: .destructive) {
                            vehicle.performanceRecords.removeAll { $0.id == record.id }
                        }
                    }
            }
        }
    }

    private func isPersonalBest(_ record: PerformanceRecord) -> Bool {
        record.id == bestDyno?.id || record.id == bestQuarter?.id
            || record.id == bestSixty?.id || record.id == bestLap?.id
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "speedometer")
                .font(.system(size: 32))
                .foregroundStyle(HUDTheme.textSecondary)
            Text("No performance records yet")
                .font(HUDTheme.body())
                .foregroundStyle(HUDTheme.textSecondary)
            Text("Log a dyno pull, 1/4 mile, 0-60, or lap time.")
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary.opacity(0.7))
            Button { showingAdd = true } label: { Label("Add First Record", systemImage: "plus") }
                .buttonStyle(.primaryAction)
                .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecordCard: View {
    var record: PerformanceRecord
    var isPersonalBest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.type.rawValue.uppercased())
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .tracking(1.5)
                Spacer()
                if isPersonalBest {
                    Label("PR", systemImage: "trophy.fill")
                        .font(HUDTheme.label(.bold))
                        .foregroundStyle(HUDTheme.amber)
                        .labelStyle(.titleAndIcon)
                }
            }

            Text(record.summary)
                .font(HUDTheme.section(.bold))
                .foregroundStyle(record.isFromLiveSession ? HUDTheme.amber : HUDTheme.textPrimary)

            // Surface the second dyno metric that summary alone hides.
            ForEach(secondaryMetrics, id: \.self) { line in
                Text(line)
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
            }

            HStack {
                if !record.location.isEmpty {
                    Text(record.location)
                        .font(HUDTheme.label())
                        .foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                Text(record.date.formatted(date: .abbreviated, time: .omitted))
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
            }

            if record.isFromLiveSession {
                Text("\(record.capturedPoints.count) live samples captured")
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.amber)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder((isPersonalBest ? HUDTheme.amber : HUDTheme.cyan).opacity(0.3), lineWidth: 1))
    }

    private var secondaryMetrics: [String] {
        var lines: [String] = []
        if record.type == .dyno, let tq = record.wheelTorque {
            lines.append("\(Int(tq)) lb-ft torque")
        }
        if record.type == .quarterMile, let trap = record.trapSpeedMph {
            lines.append(String(format: "%.0f mph trap", trap))
        }
        return lines
    }
}
