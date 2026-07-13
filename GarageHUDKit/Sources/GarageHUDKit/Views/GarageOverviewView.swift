import SwiftUI

struct GarageOverviewView: View {
    @EnvironmentObject private var store: GarageStore
    @Binding var selectedVehicleID: UUID?
    var maxSlots: Int
    var canUpgrade: Bool
    var onAddVehicle: (Int) -> Void
    var onUpgrade: () -> Void
    @State private var showingBriefing = false
    @State private var showingCompare = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                header
                fleetHealthStrip
                grid
                fleetSteward
            }
            .padding(HUDTheme.space4)
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingBriefing) { StewardBriefingView(vehicles: store.vehicles) }
        .sheet(isPresented: $showingCompare) {
            FleetComparisonView(vehicles: store.vehicles) { selectedVehicleID = $0 }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("GARAGE").font(HUDTheme.title()).foregroundStyle(HUDTheme.textPrimary)
            Spacer()
            if !store.vehicles.isEmpty {
                ShareLink(item: GarageBackup.of(store), preview: SharePreview("GarageHUD backup")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.secondaryAction)
                .accessibilityLabel("Back up garage")

                if store.vehicles.count >= 2 {
                    Button { showingCompare = true } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .buttonStyle(.secondaryAction)
                    .accessibilityLabel("Compare fleet")
                }

                Button { showingBriefing = true } label: {
                    Label("Brief me", systemImage: "text.bubble")
                }
                .buttonStyle(.primaryAction)
            }
        }
    }

    // Compact single strip so the first vehicle row sits near the initial viewport.
    private var fleetHealthStrip: some View {
        let outOfService = store.vehicles.filter { $0.serviceStatus.isInService }.count
        let review = store.vehicles.reduce(0) { $0 + Steward.observe($1).filter { $0.tone != .informational }.count }
            + Steward.observeFleet(store.vehicles).filter { $0.tone != .informational }.count
        let service = FleetHealth.serviceDue(for: store.vehicles)
        // Overdue service is the most serious fleet state (red); anything else needing attention is amber.
        let dot: Color = service.overdue > 0 ? HUDTheme.danger
            : (review > 0 || service.dueSoon > 0) ? HUDTheme.amber
            : (store.vehicles.isEmpty ? HUDTheme.textTertiary : HUDTheme.green)
        let serviceColor: Color = service.overdue > 0 ? HUDTheme.danger
            : (service.dueSoon > 0 ? HUDTheme.amber : HUDTheme.textPrimary)

        return HStack(spacing: HUDTheme.space3) {
            Circle().fill(dot).frame(width: 8, height: 8)
            healthStat("\(store.vehicles.count)", "VEHICLES")
            healthStat("\(outOfService)", "OUT OF SERVICE", outOfService > 0 ? HUDTheme.amber : HUDTheme.textPrimary)
            healthStat("\(review)", "TO REVIEW", review > 0 ? HUDTheme.amber : HUDTheme.textPrimary)
            if service.total > 0 {
                healthStat("\(service.total)", "SERVICE DUE", serviceColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HUDTheme.space3).padding(.vertical, HUDTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fleet: \(store.vehicles.count) vehicles, \(outOfService) out of service, \(review) to review\(service.total > 0 ? ", \(service.total) needing service" : "")")
    }

    private func healthStat(_ value: String, _ label: String, _ color: Color = HUDTheme.textPrimary) -> some View {
        HStack(spacing: HUDTheme.space1) {
            Text(value).font(HUDTheme.body(.semibold)).foregroundStyle(color)
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary).tracking(0.5)
        }
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: HUDTheme.space3)], spacing: HUDTheme.space3) {
            ForEach(1...maxSlots, id: \.self) { slot in
                if let vehicle = store.vehicles.first(where: { $0.garageSlot == slot }) {
                    VehicleOverviewCard(vehicle: vehicle)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedVehicleID = vehicle.id }
                } else {
                    EmptyBayCard(slot: slot).contentShape(Rectangle()).onTapGesture { onAddVehicle(slot) }
                }
            }
            if canUpgrade {
                UpgradeBayCard().contentShape(Rectangle()).onTapGesture { onUpgrade() }
            }
        }
    }

    // Fleet-level insight only when there's a genuine cross-car observation, and below the grid.
    @ViewBuilder
    private var fleetSteward: some View {
        let observations = Steward.observeFleet(store.vehicles)
        if !observations.isEmpty {
            HUDPanel(title: "Fleet Steward") {
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    ForEach(observations.prefix(2)) { StewardObservationRow($0) }
                }
            }
        }
    }
}

private struct VehicleOverviewCard: View {
    var vehicle: Vehicle

    private var attentionCount: Int {
        Steward.observe(vehicle).filter { $0.tone != .informational }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            Text(vehicle.displayName.uppercased())
                .font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
            Text(vehicle.subtitle)
                .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)

            if vehicle.serviceStatus.isInService {
                Text("OUT OF SERVICE")
                    .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.amber).tracking(1)
                    .padding(.top, HUDTheme.space1)
            }

            HStack(spacing: HUDTheme.space2) {
                Text(vehicle.latestPerformance?.summary ?? vehicle.currentHorsepowerEstimate.map { "\(Int($0)) whp" } ?? "No data yet")
                    .font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                Spacer(minLength: 0)
                if attentionCount > 0 {
                    HStack(spacing: HUDTheme.space1) {
                        Circle().fill(HUDTheme.amber).frame(width: 6, height: 6)
                        Text("\(attentionCount) to review").font(HUDTheme.label()).foregroundStyle(HUDTheme.amber)
                    }
                }
            }
            .padding(.top, HUDTheme.space1)

            HStack {
                Text(vehicle.lastActivityDate.map { "Last activity \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "No activity logged")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                Spacer(minLength: 0)
                if let miles = vehicle.currentMileage {
                    Text("\(miles.formatted(.number.grouping(.automatic))) mi")
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                }
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(HUDTheme.textTertiary)
            }
        }
        .padding(HUDTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(vehicle.displayName)\(vehicle.serviceStatus.isInService ? ", out of service" : ""), \(attentionCount) items to review\(vehicle.currentMileage.map { ", \($0) miles" } ?? "")")
    }
}

private struct EmptyBayCard: View {
    var slot: Int
    var body: some View {
        VStack(spacing: HUDTheme.space2) {
            Image(systemName: "plus.circle").font(.system(size: 24)).foregroundStyle(HUDTheme.textSecondary)
            Text("ADD VEHICLE · BAY \(slot)").font(HUDTheme.label(.medium)).foregroundStyle(HUDTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
            .strokeBorder(HUDTheme.hairline, style: StrokeStyle(lineWidth: 1, dash: [5])))
    }
}

private struct UpgradeBayCard: View {
    var body: some View {
        VStack(spacing: HUDTheme.space2) {
            Image(systemName: "lock.open").font(.system(size: 24)).foregroundStyle(HUDTheme.amber)
            Text("UNLOCK 4 MORE BAYS").font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.amber)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius)
            .strokeBorder(HUDTheme.amber.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5])))
    }
}
