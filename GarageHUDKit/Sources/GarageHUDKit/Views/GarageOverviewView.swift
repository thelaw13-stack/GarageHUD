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
    @State private var spotlightVehicleID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                header
                sinceLastVisit
                dataSafetyNotices
                spotlightSection
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

    // The front door: what changed since the app was last opened. The Steward greets you with the
    // fleet's news instead of waiting to be asked. Appears only when there's genuinely something new.
    @ViewBuilder
    private var sinceLastVisit: some View {
        if let digest = store.fleetDigest {
            HUDPanel(title: "Since you were last here",
                     caption: digest.since.formatted(.relative(presentation: .named))) {
                VStack(alignment: .leading, spacing: HUDTheme.space2) {
                    ForEach(digest.changes) { change in
                        Button {
                            if let id = change.vehicleID { selectedVehicleID = id }
                        } label: {
                            HStack(alignment: .top, spacing: HUDTheme.space2) {
                                Circle().fill(digestColor(change.tone)).frame(width: 6, height: 6).padding(.top, 6)
                                Text(change.text)
                                    .font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                if change.vehicleID != nil {
                                    Image(systemName: "chevron.right").font(.system(size: 10))
                                        .foregroundStyle(HUDTheme.textTertiary).padding(.top, 4)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Button("Dismiss") { withAnimation { store.dismissFleetDigest() } }
                        .buttonStyle(.secondaryAction)
                        .padding(.top, HUDTheme.space1)
                }
            }
            .transition(.opacity)
        }
    }

    private func digestColor(_ tone: StewardObservation.Tone) -> Color {
        switch tone {
        case .advisory: return HUDTheme.danger
        case .caution: return HUDTheme.amber
        case .informational: return HUDTheme.cyan
        }
    }

    @ViewBuilder
    private var spotlightSection: some View {
        if let vehicle = spotlightVehicle {
            VStack(alignment: .leading, spacing: HUDTheme.space2) {
                HStack {
                    Text("ACTIVE BAY")
                        .font(HUDTheme.label(.semibold))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .tracking(1.4)
                    Spacer(minLength: HUDTheme.space3)
                    bayTabs
                }
                GarageSpotlightView(vehicle: vehicle) { selectedVehicleID = vehicle.id }
                    .id(vehicle.id)
                    .transition(.opacity)
            }
        }
    }

    private var bayTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: HUDTheme.space3) {
                ForEach(store.vehicles.sorted(by: { $0.garageSlot < $1.garageSlot })) { vehicle in
                    let selected = vehicle.id == spotlightVehicle?.id
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) { spotlightVehicleID = vehicle.id }
                    } label: {
                        VStack(spacing: 4) {
                            Text("BAY \(vehicle.garageSlot)")
                                .font(HUDTheme.label(.semibold))
                                .foregroundStyle(selected ? HUDTheme.textPrimary : HUDTheme.textSecondary)
                                .tracking(1)
                            Rectangle().fill(selected ? HUDTheme.cyan : Color.clear).frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(vehicle.displayName), bay \(vehicle.garageSlot)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var spotlightVehicle: Vehicle? {
        if let spotlightVehicleID,
           let selected = store.vehicles.first(where: { $0.id == spotlightVehicleID }) {
            return selected
        }
        return store.vehicles.sorted { lhs, rhs in
            let left = spotlightScore(lhs)
            let right = spotlightScore(rhs)
            if left != right { return left > right }
            return (lhs.lastActivityDate ?? .distantPast) > (rhs.lastActivityDate ?? .distantPast)
        }.first
    }

    private func spotlightScore(_ vehicle: Vehicle) -> Int {
        var score = Steward.observe(vehicle).filter { $0.tone != .informational }.count * 12
        if vehicle.serviceStatus.isInService { score += 100 }
        switch vehicle.maintenanceDue() {
        case .overdue: score += 80
        case .dueSoon: score += 35
        case .ok: break
        }
        if !vehicle.pullReports.isEmpty { score += 10 }
        return score
    }

    @ViewBuilder
    private var dataSafetyNotices: some View {
        if let backupURL = store.loadFailureBackupURL {
            DataSafetyNotice(
                title: "LOCAL FILE PRESERVED",
                message: "GarageHUD found an unreadable garage file and saved the original before continuing.",
                url: backupURL)
        }
        if case .conflict(let snapshotURL) = store.syncStatus {
            DataSafetyNotice(
                title: "SYNC CONFLICT PRESERVED",
                message: "A newer iCloud garage was applied. Your attempted local edit was saved separately for review.",
                url: snapshotURL)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                garageTitle
                Spacer()
                headerActions
            }
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                garageTitle
                headerActions
            }
        }
    }

    private var garageTitle: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space1) {
            Text("GARAGE").font(HUDTheme.title()).foregroundStyle(HUDTheme.textPrimary)
            Text("\(store.vehicles.count) of \(maxSlots) bays occupied")
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(0.8)
        }
    }

    @ViewBuilder
    private var headerActions: some View {
        if !store.vehicles.isEmpty {
            HStack(spacing: HUDTheme.space2) {
                // The human-readable fleet sheet — a polished PDF of the whole garage. The share
                // arrow now means "share a sheet", consistently with the per-car build sheet.
                ShareLink(item: SharableFleetSheet(vehicles: store.vehicles),
                          preview: SharePreview("GarageHUD fleet sheet")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.secondaryAction)
                .accessibilityLabel("Share fleet sheet")

                // A restore file for the whole fleet — not a build sheet. The archivebox glyph reads
                // as "back up" and never masquerades as a share.
                ShareLink(item: GarageBackup.of(store),
                          preview: SharePreview("GarageHUD garage backup (restore file)")) {
                    Image(systemName: "archivebox")
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
        let urgentService = FleetHealth.mostUrgentService(in: store.vehicles)
        // Overdue service is the most serious fleet state (red); anything else needing attention is amber.
        let dot: Color = service.overdue > 0 ? HUDTheme.danger
            : (review > 0 || service.dueSoon > 0) ? HUDTheme.amber
            : (store.vehicles.isEmpty ? HUDTheme.textTertiary : HUDTheme.green)
        let serviceColor: Color = service.overdue > 0 ? HUDTheme.danger
            : (service.dueSoon > 0 ? HUDTheme.amber : HUDTheme.textPrimary)

        let dotView = Circle().fill(dot).frame(width: 8, height: 8)
        let vehiclesStat = healthStat("\(store.vehicles.count)", "VEHICLES")
        let oosStat = healthStat("\(outOfService)", "OUT OF SERVICE", outOfService > 0 ? HUDTheme.amber : HUDTheme.textPrimary)
        let reviewStat = healthStat("\(review)", "TO REVIEW", review > 0 ? HUDTheme.amber : HUDTheme.textPrimary)

        // Fit on one line when the width allows; otherwise wrap to two so no stat is hidden off-screen
        // (a horizontal scroll used to clip "SERVICE DUE" with no affordance — the eye read it as broken).
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: HUDTheme.space3) {
                dotView; vehiclesStat; oosStat; reviewStat
                if service.total > 0 { serviceDueStat(service, urgentService, serviceColor) }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: HUDTheme.space2) {
                HStack(spacing: HUDTheme.space3) { dotView; vehiclesStat; oosStat; Spacer(minLength: 0) }
                HStack(spacing: HUDTheme.space3) {
                    reviewStat
                    if service.total > 0 { serviceDueStat(service, urgentService, serviceColor) }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, HUDTheme.space3).padding(.vertical, HUDTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Fleet: \(store.vehicles.count) vehicles, \(outOfService) out of service, \(review) to review\(service.total > 0 ? ", \(service.total) needing service" : "")")
    }

    private func serviceDueStat(_ service: FleetHealth.ServiceDue,
                                _ urgentService: FleetHealth.ServiceFocus?,
                                _ color: Color) -> some View {
        healthStat("\(service.total)", "SERVICE DUE", color)
            .contentShape(Rectangle())
            .onTapGesture { if let urgentService { selectedVehicleID = urgentService.vehicleID } }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(urgentService.map { "Jump to \($0.vehicleName) for \($0.itemName)" } ?? "Jump to the car most in need of service")
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
                    ForEach(observations.prefix(2)) { obs in
                        // A note about a specific car is now a door to it, not just read-out text.
                        let target = obs.subjectID.flatMap { id in store.vehicles.first { $0.id == id }?.id }
                        HStack(alignment: .top, spacing: HUDTheme.space2) {
                            StewardObservationRow(obs)
                            if target != nil {
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11))
                                    .foregroundStyle(HUDTheme.textTertiary).padding(.top, 3)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { if let target { selectedVehicleID = target } }
                    }
                }
            }
        }
    }
}

private struct DataSafetyNotice: View {
    var title: String
    var message: String
    var url: URL

    var body: some View {
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            Image(systemName: "shield.lefthalf.filled").foregroundStyle(HUDTheme.amber)
            VStack(alignment: .leading, spacing: HUDTheme.space1) {
                Text(title).font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.amber).tracking(1)
                Text(message).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                Text(url.lastPathComponent)
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if let data = try? Data(contentsOf: url) {
                let backup = GarageBackup(data: data, filename: url.lastPathComponent)
                ShareLink(item: backup, preview: SharePreview(title)) {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.secondaryAction)
                .accessibilityLabel("Export preserved garage file")
            }
        }
        .padding(HUDTheme.space3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.amber.opacity(0.35), lineWidth: 1))
    }
}

private struct VehicleOverviewCard: View {
    var vehicle: Vehicle

    private var attentionCount: Int {
        Steward.observe(vehicle).filter { $0.tone != .informational }.count
    }

    /// A compact service badge for the card — only when the car is due/overdue (nothing to show
    /// when it's current or has no schedule; out-of-service cars are handled separately above).
    private var serviceBadge: (label: String, color: Color)? {
        switch vehicle.maintenanceDue() {
        case .overdue: return ("SERVICE OVERDUE", HUDTheme.danger)
        case .dueSoon: return ("SERVICE DUE SOON", HUDTheme.amber)
        case .ok: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            HStack(alignment: .top, spacing: HUDTheme.space2) {
                PhotoThumbnailView(photo: vehicle.heroPhoto, vehicle: vehicle, size: 58)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vehicle.displayName.uppercased())
                        .font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.78)
                    Text(vehicle.subtitle)
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(1).minimumScaleFactor(0.78)

                    if vehicle.serviceStatus.isInService {
                        Text("OUT OF SERVICE")
                            .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.amber).tracking(1)
                            .padding(.top, HUDTheme.space1)
                    } else if let service = serviceBadge {
                        HStack(spacing: HUDTheme.space1) {
                            Circle().fill(service.color).frame(width: 6, height: 6)
                            Text(service.label).font(HUDTheme.label(.semibold)).foregroundStyle(service.color).tracking(1)
                        }
                        .padding(.top, HUDTheme.space1)
                    }
                }
                Spacer(minLength: 0)
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
        .accessibilityLabel("\(vehicle.displayName)\(vehicle.serviceStatus.isInService ? ", out of service" : ""), \(attentionCount) items to review\(serviceBadge.map { ", \($0.label.lowercased())" } ?? "")\(vehicle.currentMileage.map { ", \($0) miles" } ?? "")")
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
