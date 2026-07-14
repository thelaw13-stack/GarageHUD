import SwiftUI

struct ServiceHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    @State private var pendingDeletion: BuildEvent?

    var body: some View {
        NavigationStack {
            Group {
                if vehicle.serviceLog.isEmpty {
                    ContentUnavailableView(
                        "No Service Records",
                        systemImage: "wrench.and.screwdriver",
                        description: Text("Completed maintenance will appear here."))
                } else {
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
            .background(HUDTheme.background)
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
