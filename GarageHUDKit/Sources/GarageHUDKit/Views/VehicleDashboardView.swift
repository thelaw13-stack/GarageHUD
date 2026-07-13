import SwiftUI

struct VehicleDashboardView: View {
    @Binding var vehicle: Vehicle
    /// Route a resolution that lives on another tab (parts, performance, timeline, specs) up to the
    /// detail view. When nil (e.g. previews) those options simply aren't offered.
    var onNavigate: ((VehicleDetailView.DetailTab) -> Void)? = nil
    @State private var showingAsk = false
    @State private var showingAllObservations = false
    @State private var newTask = ""
    @State private var confirmingReturn = false
    @State private var editingPart: Part?
    @State private var editingMaintenance: MaintenanceItem?
    @State private var resolving: StewardObservation?

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
    }

    // MARK: A — Identity + status

    // The car is the hero: image, name, subtitle and status compose as one first-viewport object.
    @ViewBuilder
    private var identityAndStatus: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            if vehicle.heroPhoto != nil {
                heroIdentityHeader
            } else {
                textIdentityHeader
            }
            // A compact reason line under the header — no boxed chrome — when out of service.
            if vehicle.serviceStatus.isInService, !vehicle.serviceStatus.reason.isEmpty {
                Text(vehicle.serviceStatus.reason)
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.amber.opacity(0.9))
            }
        }
        .animation(.easeOut(duration: 0.25), value: vehicle.heroPhoto?.id)   // dissolve on identity change
    }

    // Name + status laid over the car photo — the identity reads as one object, not a photo
    // attachment above a title.
    private var heroIdentityHeader: some View {
        HeroBannerView(photo: vehicle.heroPhoto, height: 210)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(vehicle.displayName.uppercased())
                        .font(HUDTheme.title()).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
                    Text(vehicle.subtitle)
                        .font(HUDTheme.label()).foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.6), radius: 4, y: 1)
                }
                .padding(HUDTheme.space3)
            }
            .overlay(alignment: .topTrailing) { statusBadge.padding(HUDTheme.space2) }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(identityAccessibilityLabel)
    }

    private var textIdentityHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(vehicle.displayName.uppercased())
                    .font(HUDTheme.title()).foregroundStyle(HUDTheme.textPrimary)
                Text(vehicle.subtitle)
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
            }
            Spacer(minLength: 0)
            statusBadge
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(identityAccessibilityLabel)
    }

    // Quiet status pill: out-of-service, else service urgency — solid enough to read over any photo.
    @ViewBuilder
    private var statusBadge: some View {
        if vehicle.serviceStatus.isInService {
            badgePill("OUT OF SERVICE", HUDTheme.amber)
        } else {
            switch vehicle.maintenanceDue() {
            case .overdue: badgePill("SERVICE OVERDUE", HUDTheme.danger)
            case .dueSoon: badgePill("SERVICE DUE SOON", HUDTheme.amber)
            case .ok: EmptyView()
            }
        }
    }

    private func badgePill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(HUDTheme.label(.semibold)).tracking(1).foregroundStyle(.white)
            .padding(.horizontal, HUDTheme.space2).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.9)))
    }

    private var identityAccessibilityLabel: String {
        var s = "\(vehicle.displayName), \(vehicle.subtitle)"
        if vehicle.serviceStatus.isInService { s += ", out of service" }
        return s
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

    // A flat metric band — not three boxed panels. Metadata reads as a quiet row so the panels
    // below (Next Step, Steward) carry the visual weight.
    private var primaryMetrics: some View {
        HStack(spacing: 0) {
            metric("POWER", vehicle.currentHorsepowerEstimate.map { "\(Int($0))" } ?? "—", "whp")
            metricDivider
            if let miles = vehicle.currentMileage {
                metric("ODOMETER", miles.formatted(.number.grouping(.automatic)), "mi")
            } else {
                metric("LATEST TEST", vehicle.latestPerformance?.summary ?? "—", "")
            }
            metricDivider
            metric("LAST ACTIVITY",
                   vehicle.lastActivityDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "—", "")
        }
        .padding(.vertical, HUDTheme.space2)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HUDTheme.hairline), alignment: .top)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HUDTheme.hairline), alignment: .bottom)
    }

    private var metricDivider: some View {
        Rectangle().fill(HUDTheme.hairline).frame(width: 1, height: 28)
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
        .padding(.horizontal, HUDTheme.space3)
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

    /// A Steward note; when it has a concrete fix, the whole row is tappable and opens the options.
    @ViewBuilder
    private func observationRow(_ observation: StewardObservation) -> some View {
        let actionable = StewardResolution.isActionable(observation, in: vehicle)
        HStack(alignment: .top, spacing: HUDTheme.space2) {
            StewardObservationRow(observation)
            if actionable {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(HUDTheme.textTertiary)
                    .padding(.top, 3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if actionable { resolving = observation } }
        .accessibilityHint(actionable ? "Double tap for ways to resolve this" : "")
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
