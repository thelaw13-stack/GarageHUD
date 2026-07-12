import SwiftUI

struct GarageOverviewView: View {
    @EnvironmentObject private var store: GarageStore
    @Binding var selectedVehicleID: UUID?
    var maxSlots: Int
    var canUpgrade: Bool
    var onAddVehicle: (Int) -> Void
    var onUpgrade: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                fleetSteward
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    ForEach(1...maxSlots, id: \.self) { slot in
                        if let vehicle = store.vehicles.first(where: { $0.garageSlot == slot }) {
                            VehicleOverviewCard(vehicle: vehicle)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedVehicleID = vehicle.id }
                        } else {
                            EmptyBayCard(slot: slot)
                                .contentShape(Rectangle())
                                .onTapGesture { onAddVehicle(slot) }
                        }
                    }
                    if canUpgrade {
                        UpgradeBayCard()
                            .contentShape(Rectangle())
                            .onTapGesture { onUpgrade() }
                    }
                }
            }
            .padding(24)
        }
        .background(HUDTheme.background)
    }

    @ViewBuilder
    private var fleetSteward: some View {
        let observations = Steward.observeFleet(store.vehicles)
        if !observations.isEmpty {
            HUDPanel(title: "Fleet Steward") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(observations) { StewardObservationRow($0) }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GARAGE OVERVIEW")
                .font(HUDTheme.monoFont(20, weight: .bold))
                .foregroundStyle(HUDTheme.cyan)
                .hudGlow(HUDTheme.cyan, radius: 6)
            Text("\(store.vehicles.count) of \(maxSlots) bays occupied")
                .font(HUDTheme.monoFont(12))
                .foregroundStyle(HUDTheme.textSecondary)
        }
    }
}

private struct UpgradeBayCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.open")
                .font(.system(size: 26))
                .foregroundStyle(HUDTheme.amber)
            Text("UNLOCK 4 MORE BAYS")
                .font(HUDTheme.monoFont(11, weight: .semibold))
                .foregroundStyle(HUDTheme.amber)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(HUDTheme.amber.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}

private struct VehicleOverviewCard: View {
    var vehicle: Vehicle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(vehicle.displayName.uppercased())
                    .font(HUDTheme.monoFont(15, weight: .bold))
                    .foregroundStyle(HUDTheme.cyan)
                Text(vehicle.subtitle)
                    .font(HUDTheme.monoFont(10))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            HStack(spacing: 18) {
                miniStat(vehicle.currentHorsepowerEstimate.map { "\(Int($0))" } ?? "—", "HP", HUDTheme.danger)
                miniStat("\(Int(vehicle.buildCompletionPercent))%", "BUILD", HUDTheme.cyan)
                miniStat(vehicle.totalInvested.formatted(.currency(code: "USD")), "INVESTED", HUDTheme.green)
            }
            HStack {
                Text("\(vehicle.installedPartsCount) parts installed")
                    .font(HUDTheme.monoFont(9))
                    .foregroundStyle(HUDTheme.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(HUDTheme.cyan.opacity(0.6))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(HUDTheme.cyan.opacity(0.3), lineWidth: 1))
        .hudGlow(HUDTheme.cyan.opacity(0.1), radius: 6)
    }

    private func miniStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(HUDTheme.monoFont(15, weight: .bold)).foregroundStyle(color)
            Text(label).font(HUDTheme.monoFont(8)).foregroundStyle(HUDTheme.textSecondary).tracking(1)
        }
    }
}

private struct EmptyBayCard: View {
    var slot: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 26))
                .foregroundStyle(HUDTheme.cyan.opacity(0.5))
            Text("ADD VEHICLE — BAY \(slot)")
                .font(HUDTheme.monoFont(11, weight: .medium))
                .foregroundStyle(HUDTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(HUDTheme.cyan.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}
