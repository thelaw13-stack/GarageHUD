import SwiftUI

struct GarageListView: View {
    @EnvironmentObject private var store: GarageStore
    @Binding var selectedVehicleID: UUID?
    var maxSlots: Int
    var canUpgrade: Bool
    var onAddVehicle: (Int) -> Void
    var onUpgrade: () -> Void

    @State private var query = ""

    private var searchResults: [SearchResult] {
        guard !query.isEmpty else { return [] }
        let needle = query.lowercased()
        var results: [SearchResult] = []
        for vehicle in store.vehicles {
            for part in vehicle.parts where part.name.lowercased().contains(needle) || part.brand.lowercased().contains(needle) {
                results.append(SearchResult(kind: "Part", title: part.name, vehicleID: vehicle.id, vehicleName: vehicle.displayName))
            }
            for note in vehicle.notes where note.title.lowercased().contains(needle) || note.body.lowercased().contains(needle) {
                results.append(SearchResult(kind: "Note", title: note.title, vehicleID: vehicle.id, vehicleName: vehicle.displayName))
            }
            for event in vehicle.buildEvents where event.title.lowercased().contains(needle) || event.eventDescription.lowercased().contains(needle) {
                results.append(SearchResult(kind: "Build Event", title: event.title, vehicleID: vehicle.id, vehicleName: vehicle.displayName))
            }
        }
        return results
    }

    var body: some View {
        VStack(spacing: 0) {
            commandBar
            List(selection: $selectedVehicleID) {
                if !query.isEmpty {
                    Section("RESULTS") {
                        if searchResults.isEmpty {
                            Text("No matches").font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        } else {
                            ForEach(searchResults) { result in
                                Button {
                                    selectedVehicleID = result.vehicleID
                                    query = ""
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title).font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                                        Text("\(result.kind) · \(result.vehicleName)")
                                            .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section {
                    ForEach(1...maxSlots, id: \.self) { slot in
                        if let vehicle = store.vehicles.first(where: { $0.garageSlot == slot }) {
                            GarageSlotRow(vehicle: vehicle, isSelected: vehicle.id == selectedVehicleID)
                                .tag(vehicle.id as UUID?)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedVehicleID = vehicle.id }
                        } else {
                            Button {
                                onAddVehicle(slot)
                            } label: {
                                EmptySlotRow(slot: slot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if canUpgrade {
                        Button(action: onUpgrade) {
                            HStack(spacing: 8) {
                                Image(systemName: "lock.open").foregroundStyle(HUDTheme.amber)
                                Text("UNLOCK 4 MORE BAYS")
                                    .font(HUDTheme.label(.semibold))
                                    .foregroundStyle(HUDTheme.amber)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(maxSlots)-BAY GARAGE")
                        .font(HUDTheme.label(.semibold))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .tracking(1.5)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(HUDTheme.background)
    }

    private var commandBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(HUDTheme.body(.bold))
                .foregroundStyle(HUDTheme.cyan)
            TextField("search parts, notes, events...", text: $query)
                .textFieldStyle(.plain)
                .font(HUDTheme.body())
                .foregroundStyle(HUDTheme.textPrimary)
            SyncStatusBadge(status: store.syncStatus)
        }
        .padding(10)
        .background(HUDTheme.panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(HUDTheme.cyan.opacity(0.35), lineWidth: 1)
        )
        .padding(10)
    }
}

private struct SyncStatusBadge: View {
    var status: GarageStore.SyncStatus

    var body: some View {
        HStack(spacing: 4) {
            switch status {
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(HUDTheme.cyan)
            case .synced:
                Image(systemName: "checkmark.icloud").foregroundStyle(HUDTheme.green)
            case .offline:
                Image(systemName: "icloud.slash").foregroundStyle(HUDTheme.textSecondary)
            case .conflict:
                Image(systemName: "exclamationmark.icloud").foregroundStyle(HUDTheme.amber)
            case .disabled:
                EmptyView()
            }
        }
        .font(.system(size: 11))
        .help(helpText)
    }

    private var helpText: String {
        switch status {
        case .syncing: "Syncing with iCloud…"
        case .synced: "Synced with iCloud"
        case .offline: "Offline — not syncing"
        case .conflict(let snapshotURL): "Sync conflict preserved at \(snapshotURL.lastPathComponent)"
        case .disabled: ""
        }
    }
}

private struct SearchResult: Identifiable {
    let id = UUID()
    let kind: String
    let title: String
    let vehicleID: UUID
    let vehicleName: String
}

private struct GarageSlotRow: View {
    var vehicle: Vehicle
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isSelected ? HUDTheme.cyan : Color.clear)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(vehicle.displayName)
                    .font(HUDTheme.body(.semibold))
                    .foregroundStyle(isSelected ? HUDTheme.cyan : HUDTheme.textPrimary)
                Text(vehicle.subtitle)
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? HUDTheme.cyan.opacity(0.12) : Color.clear)
        )
    }
}

private struct EmptySlotRow: View {
    var slot: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle")
                .foregroundStyle(HUDTheme.cyan.opacity(0.6))
            Text("ADD VEHICLE — BAY \(slot)")
                .font(HUDTheme.label(.medium))
                .foregroundStyle(HUDTheme.textSecondary)
        }
        .padding(.vertical, 6)
    }
}
