import SwiftUI

/// Phase 3 surface — where the build is headed. Shows the goal, progress toward a power target, the
/// Steward's one-line guidance about the plan's shape, and the planned parts ordered into a sensible
/// path (support and safety before power). Appears only when there's a goal or something planned, so
/// a car with no intent yet stays uncluttered. Tapping a step opens that part; the goal is editable.
struct BuildPlanSection: View {
    @Binding var vehicle: Vehicle
    /// Open a planned part for editing (wired to the dashboard's part editor).
    var onEditPart: (Part) -> Void = { _ in }

    @State private var editingGoal = false

    private var plan: BuildPlan { BuildPlanner.plan(for: vehicle) }

    var body: some View {
        if !plan.isEmpty {
            HUDPanel(title: "Build Plan", caption: plan.steps.isEmpty ? nil : "\(plan.steps.count) planned") {
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    goalHeader
                    if let frac = plan.progress.powerFraction { powerProgress(frac) }
                    if let advisory = plan.advisory { advisoryRow(advisory) }
                    if !plan.steps.isEmpty {
                        Rectangle().fill(HUDTheme.hairline).frame(height: 1)
                        Text("THE PATH").font(HUDTheme.label(.semibold))
                            .foregroundStyle(HUDTheme.textSecondary).tracking(1.2)
                        ForEach(plan.steps.prefix(6)) { stepRow($0) }
                        if plan.progress.plannedRemaining > 0 {
                            Text("~\(plan.progress.plannedRemaining.formatted(.currency(code: "USD").precision(.fractionLength(0)))) of planned parts still to buy.")
                                .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
                        }
                    }
                }
            }
            .sheet(isPresented: $editingGoal) { BuildGoalEditor(vehicle: $vehicle) }
        }
    }

    @ViewBuilder
    private var goalHeader: some View {
        if let goal = plan.goal, goal.isSet {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.summary.isEmpty ? "\(Int(goal.targetWheelHP ?? 0)) whp goal" : goal.summary)
                        .font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let target = goal.targetWheelHP {
                        Text("Target \(Int(target)) whp").font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Button("Edit") { editingGoal = true }.buttonStyle(.compactAction)
            }
        } else {
            Button { editingGoal = true } label: {
                Label("Set a build goal", systemImage: "flag").frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondaryAction)
        }
    }

    private func powerProgress(_ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Int(plan.progress.currentWHP ?? 0)) whp\(plan.progress.powerMeasured ? "" : " (est)")")
                    .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                Spacer()
                Text("\(Int((fraction * 100).rounded()))% to goal")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(HUDTheme.hairline).frame(height: 6)
                    Capsule().fill(fraction >= 1 ? HUDTheme.green : HUDTheme.cyan)
                        .frame(width: max(4, geo.size.width * fraction), height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func advisoryRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: HUDTheme.space2) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(HUDTheme.amber)
            Text(text).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepRow(_ step: PlanStep) -> some View {
        Button {
            if let part = vehicle.parts.first(where: { $0.id == step.id }) { onEditPart(part) }
        } label: {
            HStack(alignment: .top, spacing: HUDTheme.space2) {
                Text(step.priority.label)
                    .font(HUDTheme.monoFont(8, weight: .semibold)).foregroundStyle(priorityColor(step.priority))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(priorityColor(step.priority).opacity(0.5), lineWidth: 1))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        Text(step.name).font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                        if let cost = step.cost {
                            Text(cost.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        }
                    }
                    Text(step.rationale).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(HUDTheme.textTertiary).padding(.top, 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func priorityColor(_ p: PlanStep.Priority) -> Color {
        switch p {
        case .support: return HUDTheme.danger
        case .sequence: return HUDTheme.amber
        case .power: return HUDTheme.cyan
        case .other: return HUDTheme.textTertiary
        }
    }
}

/// Sets the build's intent — a one-line goal and an optional power target.
struct BuildGoalEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    @State private var summary = ""
    @State private var targetText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("e.g. Reliable 450 whp street car", text: $summary, axis: .vertical)
                }
                Section {
                    HStack {
                        TextField("450", text: $targetText)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text("whp").foregroundStyle(HUDTheme.textSecondary)
                    }
                } header: {
                    Text("Power target (optional)")
                } footer: {
                    Text("A wheel-hp target lets the Steward show real progress, and warn if the plan outpaces its support.")
                }
                if vehicle.buildGoal?.isSet == true {
                    Button("Clear goal", role: .destructive) { vehicle.buildGoal = nil; dismiss() }
                }
            }
            .navigationTitle("Build Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                summary = vehicle.buildGoal?.summary ?? ""
                targetText = vehicle.buildGoal?.targetWheelHP.map { String(Int($0)) } ?? ""
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private func save() {
        let goal = BuildGoal(summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
                             targetWheelHP: Double(targetText))
        vehicle.buildGoal = goal.isSet ? goal : nil
        dismiss()
    }
}
