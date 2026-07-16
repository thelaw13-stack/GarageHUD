import SwiftUI

struct ServiceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    @State private var pendingDeletion: BuildEvent?
    @State private var editingCost: BuildEvent?

    var body: some View {
        NavigationStack {
            Group {
                if vehicle.serviceLog.isEmpty {
                    ContentUnavailableView(
                        "No Service Records",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Completed maintenance will appear here."))
                } else {
                    VStack(spacing: 0) {
                        if vehicle.serviceSpend > 0 {
                            HStack {
                                Text("TOTAL SERVICE SPEND").font(HUDTheme.label(.semibold))
                                    .foregroundStyle(HUDTheme.textSecondary).tracking(1.2)
                                Spacer()
                                Text(vehicle.serviceSpend.formatted(.currency(code: "USD")))
                                    .font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.cyan)
                            }
                            .padding(.horizontal, HUDTheme.space4).padding(.vertical, HUDTheme.space3)
                        }
                        List {
                            ForEach(vehicle.serviceLog) { event in
                                serviceRow(event)
                                    .swipeActions {
                                        Button("Remove", role: .destructive) {
                                            pendingDeletion = event
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .background(HUDTheme.background)
            .sheet(item: $editingCost) { event in
                ServiceCostEditor(vehicle: $vehicle, event: event)
            }
            .navigationTitle("Service History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .confirmationDialog(
            "Remove this service record?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { event in
            Button("Remove Record", role: .destructive) {
                vehicle.removeServiceRecord(event.id)
                pendingDeletion = nil
            }
            Button("Keep Record", role: .cancel) { pendingDeletion = nil }
        } message: { event in
            Text("This removes \(displayName(event)) and restores the prior schedule baseline when needed.")
        }
    }

    private func serviceRow(_ event: BuildEvent) -> some View {
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .foregroundStyle(HUDTheme.cyan)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(displayName(event))
                    .font(HUDTheme.body(.semibold))
                    .foregroundStyle(HUDTheme.textPrimary)
                HStack(spacing: HUDTheme.space2) {
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                    if let mileage = event.mileage {
                        Text("\(mileage.formatted(.number.grouping(.automatic))) mi")
                    }
                }
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                Button { editingCost = event } label: {
                    if let cost = event.cost {
                        Text(cost.formatted(.currency(code: "USD")))
                            .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.cyan)
                    } else {
                        Label("Add cost", systemImage: "plus.circle")
                            .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: HUDTheme.space2)
            Button { pendingDeletion = event } label: {
                Image(systemName: "trash")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(HUDTheme.textTertiary)
            .accessibilityLabel("Remove \(displayName(event)) service record")
        }
        .padding(.vertical, HUDTheme.space1)
    }

    private func displayName(_ event: BuildEvent) -> String {
        event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: "")
    }
}

/// Set or clear what a single service cost — so lifetime maintenance spend can be tracked.
private struct ServiceCostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    let event: BuildEvent
    @State private var costText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("$").foregroundStyle(HUDTheme.textSecondary)
                        TextField("0", text: $costText)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                } header: {
                    Text(event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: ""))
                } footer: {
                    Text("What this service cost — parts, fluids, and labor. Adds to the vehicle's total service spend.")
                }
                if event.cost != nil {
                    Button("Clear cost", role: .destructive) {
                        vehicle.setBuildEventCost(event.id, nil); dismiss()
                    }
                }
            }
            .navigationTitle("Service Cost")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { costText = event.cost.map { String(format: "%g", $0) } ?? "" }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 220)
        #endif
    }

    private func save() {
        let trimmed = costText.trimmingCharacters(in: .whitespaces)
        vehicle.setBuildEventCost(event.id, trimmed.isEmpty ? nil : Double(trimmed))
        dismiss()
    }
}
