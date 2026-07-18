import SwiftUI

struct VehicleDashboardView: View {
    @Binding var vehicle: Vehicle
    /// Route a resolution that lives on another tab (parts, performance, timeline, specs) up to the
    /// detail view. When nil (e.g. previews) those options simply aren't offered.
    var onNavigate: ((VehicleDetailView.DetailTab) -> Void)? = nil
    @State private var showingAsk = false
    @State private var showingAllObservations = false
    @State private var showingServiceHistory = false
    @State private var newTask = ""
    @State private var confirmingReturn = false
    @State private var editingPart: Part?
    @State private var editingMaintenance: MaintenanceItem?
    @State private var pendingServiceDeletion: BuildEvent?
    @State private var pendingServiceItemID: UUID?
    @State private var serviceCostText = ""
    @State private var resolving: StewardObservation?

    /// One calm line of "what matters now" directly under the identity, so the condition never
    /// falls below the fold on a busy car (DD-001, Dashboard). It's the Steward's next step —
    /// an existing, tested judgment — not a new claim. A line that names an action must BE
    /// actionable: tapping it opens the source observation's resolution options (the same flow
    /// as the Steward rows). Only when the fix lives elsewhere on this screen (e.g. the rebuild
    /// checklist right below) does it stay a plain line.
    @ViewBuilder
    private var conditionLine: some View {
        if let step = Steward.nextStep(vehicle) {
            let resolvable = step.source.map { StewardResolution.isActionable($0, in: vehicle) } ?? false
            let row = HStack(alignment: .firstTextBaseline, spacing: HUDTheme.space2) {
                Text("NEXT").font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textTertiary).tracking(1.5)
                Text(step.action).font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if resolvable {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(HUDTheme.textTertiary)
                }
            }
            if resolvable, let source = step.source {
                Button { resolving = source } label: { row }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows ways to resolve this")
            } else {
                row
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                VehicleIdentitySurface(vehicle: vehicle)
                conditionLine           // DD-001: what matters now, never below the fold
                stewardPanel            // C — required attention (quieter, supporting)
                buildAssessment         // synthesis
                BuildPlanSection(vehicle: $vehicle, onEditPart: { editingPart = $0 })  // where it's headed
                rebuildChecklist        // D — contextual workflow
                maintenancePanel
                detailsPanel            // E — secondary specs / build detail
                recentActivity          // F — memory
            }
            .padding(HUDTheme.space4)
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAsk) { AskStewardView(vehicle: vehicle) }
        .sheet(isPresented: $showingAllObservations) { allObservationsSheet }
        .sheet(isPresented: $showingServiceHistory) { ServiceHistoryView(vehicle: $vehicle) }
        .sheet(item: $editingPart) { part in AddEditPartView(vehicle: $vehicle, partID: part.id) }
        .sheet(item: $editingMaintenance) { item in
            MaintenanceEditorView(vehicle: $vehicle, itemID: item.id)
        }
        .confirmationDialog(resolving?.statement ?? "Resolve",
                            isPresented: Binding(get: { resolving != nil },
                                                 set: { if !$0 { resolving = nil } }),
                            titleVisibility: .visible,
                            presenting: resolving) { observation in
            resolutionButtons(for: observation)
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
        .confirmationDialog("Remove this service record?",
                            isPresented: Binding(
                                get: { pendingServiceDeletion != nil },
                                set: { if !$0 { pendingServiceDeletion = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingServiceDeletion) { event in
            Button("Remove Record", role: .destructive) {
                vehicle.removeServiceRecord(event.id)
                pendingServiceDeletion = nil
            }
            Button("Keep Record", role: .cancel) { pendingServiceDeletion = nil }
        } message: { event in
            Text("This removes \(serviceDisplayName(event)) from history. If it reset a maintenance schedule, the prior service date and mileage will be restored.")
        }
        .alert("Log this service",
               isPresented: Binding(get: { pendingServiceItemID != nil },
                                    set: { if !$0 { pendingServiceItemID = nil } })) {
            TextField("Cost (optional)", text: $serviceCostText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Button("Log") {
                if let id = pendingServiceItemID {
                    vehicle.markMaintenanceDone(id, cost: Double(serviceCostText.trimmingCharacters(in: .whitespaces)))
                }
                pendingServiceItemID = nil
            }
            Button("Cancel", role: .cancel) { pendingServiceItemID = nil }
        } message: {
            Text("Enter what it cost, or leave it blank — the service logs either way.")
        }
    }

    // MARK: C — Steward (top two + view all)

    private var stewardPanel: some View {
        let observations = Steward.observe(vehicle)
        return HUDPanel(title: "Steward", caption: "Actions only when earned") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                if observations.isEmpty {
                    Text("Steward is watching. Nothing stands out yet.")
                        .font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
                } else {
                    ForEach(observations.prefix(2)) { observation in
                        observationRow(observation)
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
                    observationRow(observation)
                }
            }
            .padding(HUDTheme.space4)
        }
        .background(HUDTheme.background)
    }

    /// A Steward note with a small door on the right — "Resolve" when there's a concrete fix,
    /// otherwise a quiet "Review" into the fuller evidence. Restrained, never a heroic button.
    @ViewBuilder
    private func observationRow(_ observation: StewardObservation) -> some View {
        let actionable = StewardResolution.isActionable(observation, in: vehicle)
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            StewardObservationRow(observation)
            Spacer(minLength: 0)
            if actionable {
                Button("Resolve") { resolving = observation }
                    .buttonStyle(.compactAction)
                    .accessibilityHint("Ways to resolve this")
            } else {
                Button("Review") { showingAllObservations = true }
                    .buttonStyle(.compactAction)
                    .accessibilityHint("See the full evidence")
            }
        }
    }

    @ViewBuilder
    private func resolutionButtons(for observation: StewardObservation) -> some View {
        ForEach(StewardResolution.options(for: observation, in: vehicle)) { option in
            Button(option.title) { perform(option.action) }
        }
        Button("Not now", role: .cancel) {}
    }

    private func perform(_ action: ResolutionAction) {
        switch action {
        case .markServiced(let id):      vehicle.markMaintenanceDone(id)
        case .editSchedule(let id):      editingMaintenance = vehicle.maintenance.first { $0.id == id }
        case .markBackInService:         confirmingReturn = true
        case .confirmStock(let cat):     vehicle.confirmedStockSystems.insert(cat)
        case .addPart:                   onNavigate?(.parts)
        case .reviewParts:               onNavigate?(.parts)
        case .logPerformance:            onNavigate?(.performance)
        case .logActivity:               onNavigate?(.timeline)
        case .editEnvelope:              onNavigate?(.specs)
        }
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
                            let done = vehicle.maintenanceAlreadyDone(item.id)
                            Button(done ? "Undo" : "Mark done") {
                                if done {
                                    pendingServiceDeletion = vehicle.latestServiceRecord(for: item.id)
                                } else {
                                    serviceCostText = ""
                                    pendingServiceItemID = item.id
                                }
                            }
                                .buttonStyle(.compactAction)
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
                    Text(serviceDisplayName(event))
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textPrimary)
                    Spacer(minLength: 0)
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    Button { pendingServiceDeletion = event } label: {
                        Image(systemName: "trash")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(HUDTheme.textTertiary)
                    .accessibilityLabel("Remove \(serviceDisplayName(event)) service record")
                }
            }
            Button { showingServiceHistory = true } label: {
                Label(log.count > 4 ? "Manage all \(log.count) records" : "Manage service history",
                      systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(.compactAction)
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
            // If we've learned a driving rate, project that mileage into plain English.
            if remaining > 0, let projected = item.projectedMileageDueDate(
                currentMileage: vehicle.currentMileage, milesPerDay: vehicle.milesPerDay) {
                detail += " (~\(projected.formatted(.relative(presentation: .named))) at your pace)"
            }
        }
        return detail
    }

    private func maintenanceColor(_ d: MaintenanceItem.Due) -> Color {
        switch d { case .overdue: return HUDTheme.danger; case .dueSoon: return HUDTheme.amber; case .ok: return HUDTheme.green }
    }
    private func maintenanceStatusText(_ d: MaintenanceItem.Due) -> String {
        switch d { case .overdue: return "Overdue"; case .dueSoon: return "Due soon"; case .ok: return "OK" }
    }
    private func serviceDisplayName(_ event: BuildEvent) -> String {
        event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: "")
    }
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
                    if let torque = vehicle.performanceRecords.filter({ $0.type == .dyno && ($0.wheelTorque ?? 0) > 0 }).sorted(by: { $0.date > $1.date }).first?.wheelTorque ?? vehicle.factoryTorque {
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
        HUDPanel(title: "Memory", caption: "Recent") {
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
