import SwiftUI

struct VehicleDashboardView: View {
    @Binding var vehicle: Vehicle
    @State private var showingAsk = false
    @State private var showingAllObservations = false
    @State private var newTask = ""
    @State private var confirmingReturn = false
    @State private var editingPart: Part?
    @State private var editingMaintenance: MaintenanceItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                identityAndStatus       // A — identity + current status
                nextStep                // the single most useful thing to do next
                primaryMetrics          // B — three primary metrics
                stewardPanel            // C — required attention
                buildAssessment         // synthesis
                rebuildChecklist        // D — contextual workflow
                maintenancePanel
                detailsPanel            // E — secondary specs / build detail
                recentActivity          // F
            }
            .padding(HUDTheme.space4)
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAsk) { AskStewardView(vehicle: vehicle) }
        .sheet(isPresented: $showingAllObservations) { allObservationsSheet }
        .sheet(item: $editingPart) { part in AddEditPartView(vehicle: $vehicle, partID: part.id) }
        .sheet(item: $editingMaintenance) { item in
            MaintenanceEditorView(vehicle: $vehicle, itemID: item.id)
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

    // MARK: A — Identity + status

    private var identityAndStatus: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            Text(vehicle.displayName.uppercased())
                .font(HUDTheme.title())
                .foregroundStyle(HUDTheme.textPrimary)
            Text(vehicle.subtitle)
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
            serviceStrip
        }
    }

    @ViewBuilder
    private var serviceStrip: some View {
        if vehicle.serviceStatus.isInService {
            HStack(spacing: HUDTheme.space2) {
                Image(systemName: "wrench.and.screwdriver.fill").font(.system(size: 13))
                VStack(alignment: .leading, spacing: 1) {
                    Text("OUT OF SERVICE").font(HUDTheme.label(.semibold)).tracking(1.5)
                    if !vehicle.serviceStatus.reason.isEmpty {
                        Text(vehicle.serviceStatus.reason)
                            .font(HUDTheme.label()).foregroundStyle(HUDTheme.amber.opacity(0.85))
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(HUDTheme.amber)
            .padding(.horizontal, HUDTheme.space3).padding(.vertical, HUDTheme.space2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: HUDTheme.space2).fill(HUDTheme.amber.opacity(0.12)))
            .padding(.top, HUDTheme.space1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Out of service. \(vehicle.serviceStatus.reason)")
        }
    }

    // The Steward's single recommended next step, when there is one.
    @ViewBuilder
    private var nextStep: some View {
        if let step = Steward.nextStep(vehicle) {
            HUDPanel(title: "Next Step") {
                VStack(alignment: .leading, spacing: HUDTheme.space2) {
                    Text(step.action)
                        .font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(step.rationale)
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Next step: \(step.action). \(step.rationale)")
            }
        }
    }

    // MARK: B — Three primary metrics

    private var primaryMetrics: some View {
        HStack(spacing: HUDTheme.space3) {
            metric("POWER", vehicle.currentHorsepowerEstimate.map { "\(Int($0))" } ?? "—", "whp")
            if let miles = vehicle.currentMileage {
                metric("ODOMETER", miles.formatted(.number.grouping(.automatic)), "mi")
            } else {
                metric("LATEST TEST", vehicle.latestPerformance?.summary ?? "—", "")
            }
            metric("LAST ACTIVITY",
                   vehicle.lastActivityDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "—", "")
        }
    }

    private func metric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: HUDTheme.space1) {
            Text(label).font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary).tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(HUDTheme.section()).foregroundStyle(HUDTheme.textPrimary)
                if !unit.isEmpty { Text(unit).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(HUDTheme.space3)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) \(unit)")
    }

    // MARK: C — Steward (top two + view all)

    private var stewardPanel: some View {
        let observations = Steward.observe(vehicle)
        return HUDPanel(title: "Steward") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                if observations.isEmpty {
                    Text("Steward is watching. Nothing stands out yet.")
                        .font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
                } else {
                    ForEach(observations.prefix(2)) { observation in
                        VStack(alignment: .leading, spacing: HUDTheme.space2) {
                            StewardObservationRow(observation)
                            resolveAction(for: observation)
                        }
                    }
                    if observations.count > 2 {
                        Button("View all \(observations.count)") { showingAllObservations = true }
                            .buttonStyle(.secondaryAction)
                    }
                }
                Button {
                    showingAsk = true
                } label: {
                    Label("Ask Steward", systemImage: "waveform").frame(maxWidth: .infinity)
                }
                .buttonStyle(.primaryAction)
            }
        }
    }

    private var allObservationsSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                Text("STEWARD").font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary).tracking(1.5)
                ForEach(Steward.observe(vehicle)) { observation in
                    VStack(alignment: .leading, spacing: HUDTheme.space2) {
                        StewardObservationRow(observation)
                        resolveAction(for: observation)
                    }
                }
            }
            .padding(HUDTheme.space4)
        }
        .background(HUDTheme.background)
    }

    /// Resolve an undocumented gap in place — compact, shared action styling.
    @ViewBuilder
    private func resolveAction(for observation: StewardObservation) -> some View {
        if let category = gapCategory(observation), vehicle.knowledge(of: category) == .undocumented {
            Button("Confirm \(category.rawValue.lowercased()) is factory-stock") {
                vehicle.confirmedStockSystems.insert(category)
            }
            .buttonStyle(.attentionAction)
            .padding(.leading, HUDTheme.space4)
        }
    }

    private func gapCategory(_ observation: StewardObservation) -> PartCategory? {
        guard observation.ruleID.hasPrefix("gap.") else { return nil }
        return PartCategory(rawValue: String(observation.ruleID.dropFirst("gap.".count)))
    }

    // MARK: synthesis — Build Assessment

    @ViewBuilder
    private var buildAssessment: some View {
        if let a = Steward.assess(vehicle) {
            HUDPanel(title: "Build Assessment") {
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    Text(a.powerSummary).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    Text(a.headline).font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(HUDTheme.hairline)
                    ForEach(a.subsystems) { sub in
                        HStack(alignment: .top, spacing: HUDTheme.space3) {
                            Circle().fill(assessmentColor(sub.status)).frame(width: 8, height: 8).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sub.label).font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                                Text("\(assessmentStatusText(sub.status)) · \(sub.role)")
                                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            if sub.planned {
                                Text("PLANNED")
                                    .font(HUDTheme.monoFont(8, weight: .semibold))
                                    .foregroundStyle(HUDTheme.cyan)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .overlay(Capsule().strokeBorder(HUDTheme.cyan.opacity(0.4), lineWidth: 1))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(sub.label): \(assessmentStatusText(sub.status))")
                    }
                    Text(a.confidence.label.uppercased())
                        .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textTertiary).tracking(1)
                }
            }
        }
    }

    private func assessmentColor(_ s: BuildAssessment.Status) -> Color {
        switch s {
        case .supported: return HUDTheme.green
        case .openItem: return HUDTheme.danger
        case .undocumented: return HUDTheme.amber
        }
    }
    private func assessmentStatusText(_ s: BuildAssessment.Status) -> String {
        switch s {
        case .supported: return "Covered"
        case .openItem: return "Open item"
        case .undocumented: return "Not documented"
        }
    }

    // MARK: D — Rebuild workflow

    @ViewBuilder
    private var rebuildChecklist: some View {
        if vehicle.serviceStatus.isInService {
            HUDPanel(title: rebuildTitle) {
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    subsectionHeader("WORK REQUIRED")
                    ForEach(vehicle.serviceStatus.checklist) { task in
                        HStack(alignment: .top, spacing: HUDTheme.space3) {
                            Button { toggleTask(task.id) } label: {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? HUDTheme.green : HUDTheme.textSecondary)
                                    .frame(width: 24, height: 24)   // touch target
                            }
                            .buttonStyle(.plain)
                            Text(task.title)
                                .font(HUDTheme.body())
                                .foregroundStyle(task.isDone ? HUDTheme.textSecondary : HUDTheme.textPrimary)
                                .strikethrough(task.isDone, color: HUDTheme.textSecondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .contextMenu { Button("Delete", role: .destructive) { deleteTask(task.id) } }
                    }
                    HStack(spacing: HUDTheme.space2) {
                        Image(systemName: "plus").foregroundStyle(HUDTheme.cyan).font(.system(size: 12))
                        TextField("Add a task…", text: $newTask)
                            .font(HUDTheme.body()).textFieldStyle(.plain).onSubmit(addTask)
                    }

                    let flagged = vehicle.partsFlaggedForRebuild
                    if !flagged.isEmpty {
                        Divider().overlay(HUDTheme.hairline)
                        subsectionHeader("PARTS TO INSPECT / REPLACE")
                        ForEach(flagged) { part in
                            Button { editingPart = part } label: {
                                HStack(spacing: HUDTheme.space2) {
                                    Image(systemName: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(HUDTheme.amber)
                                    Text(part.name).font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(HUDTheme.textTertiary)
                                }
                                .frame(minHeight: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        attemptReturn()
                    } label: {
                        Label("Mark back in service", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.secondaryAction)
                    .padding(.top, HUDTheme.space1)
                }
            }
        }
    }

    private func subsectionHeader(_ text: String) -> some View {
        Text(text).font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textTertiary).tracking(1)
    }

    private var rebuildTitle: String {
        if let p = vehicle.serviceStatus.progressText { return "Rebuild · \(p)" }
        return "Rebuild"
    }

    private func attemptReturn() {
        let remaining = vehicle.serviceStatus.checklist.count - vehicle.serviceStatus.completedCount
        if remaining > 0 { confirmingReturn = true } else { vehicle.markBackInService() }
    }
    private func toggleTask(_ id: UUID) {
        if let i = vehicle.serviceStatus.checklist.firstIndex(where: { $0.id == id }) {
            vehicle.serviceStatus.checklist[i].isDone.toggle()
        }
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

    // MARK: Maintenance

    @State private var newMaintName = ""

    private var maintenancePanel: some View {
        HUDPanel(title: "Maintenance") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                if vehicle.maintenance.isEmpty {
                    Text("No scheduled maintenance yet — add oil, fluids, or filters to track them.")
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                }
                Group {
                    ForEach(vehicle.maintenance) { item in
                        let due = item.due(currentMileage: vehicle.currentMileage)
                        HStack(alignment: .top, spacing: HUDTheme.space3) {
                            Circle().fill(maintenanceColor(due)).frame(width: 8, height: 8).padding(.top, 4)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                                Text(maintenanceDetail(item))
                                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Button("Mark done") { markServiced(item.id) }.buttonStyle(.compactAction)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingMaintenance = item }
                        .contextMenu {
                            Button("Edit…") { editingMaintenance = item }
                            Button("Remove", role: .destructive) { removeMaintenance(item.id) }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(item.name): \(maintenanceStatusText(due))")
                    }
                    HStack(spacing: HUDTheme.space2) {
                        Image(systemName: "plus").foregroundStyle(HUDTheme.cyan).font(.system(size: 12))
                        TextField("Add an item (6-month interval)…", text: $newMaintName)
                            .font(HUDTheme.body()).textFieldStyle(.plain).onSubmit(addMaintenance)
                    }
                    serviceHistory
                }
            }
        }
    }

    @ViewBuilder
    private var serviceHistory: some View {
        let log = vehicle.serviceLog
        if !log.isEmpty {
            Divider().overlay(HUDTheme.hairline).padding(.vertical, HUDTheme.space1)
            Text("SERVICE HISTORY").font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textSecondary).tracking(1)
            ForEach(log.prefix(4)) { event in
                HStack(spacing: HUDTheme.space2) {
                    Text(event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: ""))
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textPrimary)
                    Spacer(minLength: 0)
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                }
            }
            if log.count > 4 {
                Text("+ \(log.count - 4) more in the timeline")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            }
        }
    }

    private func maintenanceDetail(_ item: MaintenanceItem) -> String {
        let due = item.due(currentMileage: vehicle.currentMileage)
        var interval = "every \(item.intervalMonths) mo"
        if let miles = item.intervalMiles {
            interval += " / \(miles.formatted(.number.grouping(.automatic))) mi"
        }
        var detail = "\(maintenanceStatusText(due)) · \(interval) · due \(item.dueDate().formatted(date: .abbreviated, time: .omitted))"
        if let remaining = item.milesUntilDue(currentMileage: vehicle.currentMileage) {
            detail += remaining > 0
                ? " or in \(remaining.formatted(.number.grouping(.automatic))) mi"
                : " · \((-remaining).formatted(.number.grouping(.automatic))) mi over"
        }
        return detail
    }

    private func maintenanceColor(_ d: MaintenanceItem.Due) -> Color {
        switch d { case .overdue: return HUDTheme.danger; case .dueSoon: return HUDTheme.amber; case .ok: return HUDTheme.green }
    }
    private func maintenanceStatusText(_ d: MaintenanceItem.Due) -> String {
        switch d { case .overdue: return "Overdue"; case .dueSoon: return "Due soon"; case .ok: return "OK" }
    }
    private func markServiced(_ id: UUID) { vehicle.markMaintenanceDone(id) }
    private func removeMaintenance(_ id: UUID) { vehicle.maintenance.removeAll { $0.id == id } }
    private func addMaintenance() {
        let n = newMaintName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        vehicle.maintenance.append(MaintenanceItem(name: n, intervalMonths: 6, lastServiced: .now))
        newMaintName = ""
    }

    // MARK: E — Secondary detail

    private var detailsPanel: some View {
        HUDPanel(title: "Build Detail") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                if !vehicle.engineDescription.isEmpty {
                    StatReadout(label: "Engine", value: vehicle.engineDescription)
                }
                if !vehicle.drivetrainDescription.isEmpty {
                    StatReadout(label: "Drivetrain", value: vehicle.drivetrainDescription)
                }
                HStack(spacing: HUDTheme.space5) {
                    detailStat("\(vehicle.installedPartsCount)", "PARTS")
                    if let torque = vehicle.performanceRecords.filter({ $0.type == .dyno }).sorted(by: { $0.date > $1.date }).first?.wheelTorque ?? vehicle.factoryTorque {
                        detailStat("\(Int(torque))", "LB-FT")
                    }
                    if let ratio = vehicle.powerToWeight { detailStat(String(format: "%.1f", ratio), "LB/HP") }
                }
            }
        }
    }

    private func detailStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary).tracking(1)
        }
    }

    // MARK: F — Recent activity

    private var recentActivity: some View {
        HUDPanel(title: "Recent Activity") {
            let events = Array(vehicle.buildEvents.sorted { $0.date > $1.date }.prefix(5))
            if events.isEmpty {
                Text("No build events logged yet.")
                    .font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: HUDTheme.space2) {
                    ForEach(events) { event in
                        HStack(spacing: HUDTheme.space2) {
                            Circle().fill(HUDTheme.textTertiary).frame(width: 5, height: 5)
                            Text(event.title).font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                            Spacer(minLength: 0)
                            Text(event.date.formatted(date: .abbreviated, time: .omitted))
                                .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        }
                    }
                }
            }
        }
    }
}
