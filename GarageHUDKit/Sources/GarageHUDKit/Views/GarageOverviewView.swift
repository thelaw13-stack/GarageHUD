import SwiftUI

struct GarageOverviewView: View {
    @EnvironmentObject private var store: GarageStore
    @Binding var selectedVehicleID: UUID?
    var maxSlots: Int
    var canUpgrade: Bool
    var onAddVehicle: (Int) -> Void
    var onUpgrade: () -> Void
    @State private var showingBriefing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                header
                fleetHealth
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
        .sheet(isPresented: $showingBriefing) {
            StewardBriefingView(vehicles: store.vehicles)
        }
    }

    /// Fleet health summary — the answer to "how is my garage today?" at a glance (brief §6).
    private var fleetHealth: some View {
        let vehicles = store.vehicles
        let observations = vehicles.flatMap { Steward.observe($0) } + Steward.observeFleet(vehicles)
        let advisories = observations.filter { $0.tone == .advisory }.count
        let cautions = observations.filter { $0.tone == .caution }.count
        let attention = advisories + cautions

        let status: (dot: Color, headline: String, sub: String)
        if vehicles.isEmpty {
            status = (HUDTheme.textTertiary, "No vehicles yet", "Add a car to begin its record.")
        } else if attention == 0 {
            status = (HUDTheme.green, "All clear", "Nothing needs your attention right now.")
        } else {
            let color = advisories > 0 ? HUDTheme.danger : HUDTheme.amber
            status = (color, "\(attention) item\(attention == 1 ? "" : "s") need attention",
                      "Across \(vehicles.count) vehicle\(vehicles.count == 1 ? "" : "s").")
        }

        return HUDPanel(title: "Fleet Health") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                HStack(alignment: .top, spacing: HUDTheme.space3) {
                    Circle().fill(status.dot).frame(width: 10, height: 10)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: HUDTheme.space1) {
                        Text(status.headline)
                            .font(HUDTheme.section())
                            .foregroundStyle(HUDTheme.textPrimary)
                        Text(status.sub)
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                }
                if !vehicles.isEmpty {
                    Divider().overlay(HUDTheme.hairline)
                    HStack(spacing: HUDTheme.space5) {
                        healthStat("\(vehicles.count)", "VEHICLES")
                        healthStat(vehicles.reduce(0) { $0 + $1.totalInvested }.formatted(.currency(code: "USD").precision(.fractionLength(0))), "INVESTED", HUDTheme.green)
                        healthStat("\(attention)", "TO REVIEW", attention > 0 ? HUDTheme.amber : HUDTheme.textPrimary)
                    }
                }
            }
        }
    }

    private func healthStat(_ value: String, _ label: String, _ color: Color = HUDTheme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(HUDTheme.body(.semibold)).foregroundStyle(color)
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary).tracking(1)
        }
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GARAGE")
                    .font(HUDTheme.title())
                    .foregroundStyle(HUDTheme.textPrimary)
                Text("\(store.vehicles.count) of \(maxSlots) bays occupied")
                    .font(HUDTheme.monoFont(12))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            Spacer()
            if !store.vehicles.isEmpty {
                Button { showingBriefing = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "text.bubble")
                        Text("BRIEF ME").font(HUDTheme.monoFont(10, weight: .semibold)).tracking(1)
                    }
                    .foregroundStyle(HUDTheme.cyan)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(Capsule().strokeBorder(HUDTheme.cyan.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
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
            RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
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
                    .foregroundStyle(HUDTheme.textPrimary)
                Text(vehicle.subtitle)
                    .font(HUDTheme.monoFont(10))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            HStack(spacing: 18) {
                miniStat(vehicle.currentHorsepowerEstimate.map { "\(Int($0))" } ?? "—", "HP", HUDTheme.textPrimary)
                miniStat("\(Int(vehicle.buildCompletionPercent))%", "BUILD", HUDTheme.textPrimary)
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
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
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
            RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
                .strokeBorder(HUDTheme.cyan.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}
