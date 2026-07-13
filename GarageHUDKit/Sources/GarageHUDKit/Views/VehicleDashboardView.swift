import SwiftUI

struct VehicleDashboardView: View {
    @Binding var vehicle: Vehicle
    @State private var showingAsk = false
    @State private var newTask = ""
    @State private var confirmingReturn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                keyMetrics
                buildProgress
                nextSteps
                rebuildChecklist
                recentActivity
            }
            .padding(24)
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAsk) {
            AskStewardView(vehicle: vehicle)
        }
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
        let observations = Steward.observe(vehicle)
        return HUDPanel(title: "Steward") {
            VStack(alignment: .leading, spacing: 14) {
                if observations.isEmpty {
                    Text("Steward is watching. Nothing stands out yet — log parts, a dyno pull, or a documented total and observations will appear here.")
                        .font(HUDTheme.monoFont(11))
                        .foregroundStyle(HUDTheme.textSecondary)
                } else {
                    ForEach(observations) { observation in
                        VStack(alignment: .leading, spacing: 8) {
                            StewardObservationRow(observation)
                            resolveAction(for: observation)
                        }
                    }
                }

                Button { showingAsk = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                        Text("ASK STEWARD")
                            .font(HUDTheme.monoFont(11, weight: .semibold))
                            .tracking(1.5)
                    }
                    .foregroundStyle(HUDTheme.cyan)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Close the loop where the owner actually sees it: an undocumented gap can be resolved
    /// inline — either the factory system is confirmed stock (→ a firm caution) or it's on the
    /// car and just needs logging. No trip to the Specs tab required.
    @ViewBuilder
    private func resolveAction(for observation: StewardObservation) -> some View {
        if let category = gapCategory(observation), vehicle.knowledge(of: category) == .undocumented {
            Button {
                vehicle.confirmedStockSystems.insert(category)
            } label: {
                Label("Confirm \(category.rawValue.lowercased()) is factory-stock", systemImage: "checkmark.seal")
                    .font(HUDTheme.monoFont(9, weight: .semibold))
                    .foregroundStyle(HUDTheme.amber)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(HUDTheme.amber.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 22)
        }
    }

    /// The part category a `gap.*` observation is about, if the record leaves it undocumented.
    private func gapCategory(_ observation: StewardObservation) -> PartCategory? {
        guard observation.ruleID.hasPrefix("gap.") else { return nil }
        return PartCategory(rawValue: String(observation.ruleID.dropFirst("gap.".count)))
    }

    /// Shown only while the car is out of service — what's left before it's back together.
    @ViewBuilder
    private var rebuildChecklist: some View {
        if vehicle.serviceStatus.isInService {
            HUDPanel(title: rebuildTitle) {
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    ForEach($vehicle.serviceStatus.checklist) { $task in
                        HStack(alignment: .top, spacing: HUDTheme.space3) {
                            Button { task.isDone.toggle() } label: {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? HUDTheme.green : HUDTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                            Text(task.title)
                                .font(HUDTheme.body())
                                .foregroundStyle(task.isDone ? HUDTheme.textSecondary : HUDTheme.textPrimary)
                                .strikethrough(task.isDone, color: HUDTheme.textSecondary)
                            Spacer(minLength: 0)
                            Button { deleteTask(task.id) } label: {
                                Image(systemName: "minus.circle").foregroundStyle(HUDTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: HUDTheme.space2) {
                        Image(systemName: "plus").foregroundStyle(HUDTheme.cyan).font(.system(size: 12))
                        TextField("Add a task…", text: $newTask)
                            .font(HUDTheme.body())
                            .textFieldStyle(.plain)
                            .onSubmit(addTask)
                    }
                    .padding(.top, HUDTheme.space1)

                    Button { attemptReturn() } label: {
                        HStack(spacing: HUDTheme.space2) {
                            Image(systemName: "checkmark.seal")
                            Text("MARK BACK IN SERVICE")
                                .font(HUDTheme.label(.semibold)).tracking(1.5)
                        }
                        .foregroundStyle(HUDTheme.green)
                        .padding(.horizontal, HUDTheme.space3).padding(.vertical, 9)
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.green.opacity(0.45), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, HUDTheme.space2)
                }
            }
            .confirmationDialog("Mark \(vehicle.displayName) back in service?",
                                isPresented: $confirmingReturn, titleVisibility: .visible) {
                Button("Back in service") { vehicle.markBackInService() }
                Button("Keep working", role: .cancel) {}
            } message: {
                let remaining = vehicle.serviceStatus.checklist.count - vehicle.serviceStatus.completedCount
                Text(remaining > 0
                     ? "\(remaining) checklist item\(remaining == 1 ? "" : "s") still open. This logs a build event and clears the checklist."
                     : "This logs a build event and clears the checklist.")
            }
        }
    }

    private func attemptReturn() {
        let remaining = vehicle.serviceStatus.checklist.count - vehicle.serviceStatus.completedCount
        if remaining > 0 { confirmingReturn = true } else { vehicle.markBackInService() }
    }

    private var rebuildTitle: String {
        if let p = vehicle.serviceStatus.progressText { return "Rebuild Checklist · \(p)" }
        return "Rebuild Checklist"
    }

    private func addTask() {
        let t = newTask.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        vehicle.serviceStatus.checklist.append(ServiceTask(title: t))
        newTask = ""
    }

    private func deleteTask(_ id: UUID) {
        vehicle.serviceStatus.checklist.removeAll { $0.id == id }
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
