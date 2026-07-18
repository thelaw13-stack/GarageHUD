import SwiftUI

/// A composed vehicle identity surface: photo, status, next action, and primary metrics live in
/// one place so the dashboard opens with the car's current condition instead of a stack of peers.
struct VehicleIdentitySurface: View {
    var vehicle: Vehicle
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var image: PlatformImage?
    @State private var loadedFilename: String?

    private var nextStep: NextStep? { Steward.nextStep(vehicle) }
    private var reviewCount: Int { Steward.observe(vehicle).filter { $0.tone != .informational }.count }

    var body: some View {
        VStack(spacing: 0) {
            photoBand
            content
                .padding(HUDTheme.space4)
                .background(HUDTheme.panelBackground)
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .task(id: vehicle.heroPhoto?.filename) { await loadHeroImage() }
    }

    private var photoBand: some View {
        photoField
            .frame(maxWidth: .infinity)
            .frame(height: horizontalSizeClass == .compact ? 176 : 230)
            .clipped()
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, HUDTheme.panelBackground.opacity(0.54)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .frame(height: 72)
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    private var photoField: some View {
        if let image {
            #if canImport(AppKit)
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
            #else
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
            #endif
        } else {
            VehicleVisualFallback(vehicle: vehicle, style: .hero)
        }
    }

    private func loadHeroImage() async {
        guard let photo = vehicle.heroPhoto else {
            image = nil
            loadedFilename = nil
            return
        }
        guard photo.filename != loadedFilename else { return }
        let filename = photo.filename
        let decoded: PlatformImage? = await Task.detached(priority: .userInitiated) {
            guard let data = ImageStore.load(filename: filename) else { return nil }
            return PlatformImage(data: data)
        }.value
        image = decoded
        loadedFilename = filename
    }

    private var content: some View {
        Group {
            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: HUDTheme.space4) {
                    identityBlock
                    statusAndMetrics(alignment: .leading)
                }
            } else {
                HStack(alignment: .bottom, spacing: HUDTheme.space4) {
                    identityBlock
                    Spacer(minLength: HUDTheme.space3)
                    statusAndMetrics(alignment: .trailing)
                        .frame(maxWidth: 360)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            HStack(spacing: HUDTheme.space2) {
                Circle().fill(identityColor).frame(width: 8, height: 8)
                Text(identityState.uppercased())
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .tracking(1.2)
            }

            Text(vehicle.displayName.uppercased())
                .font(HUDTheme.title())
                .foregroundStyle(HUDTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(vehicle.subtitle)
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            nextAction
                .padding(.top, HUDTheme.space2)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    @ViewBuilder
    private var nextAction: some View {
        if let nextStep {
            HStack(alignment: .top, spacing: HUDTheme.space3) {
                Rectangle()
                    .fill(HUDTheme.amber)
                    .frame(width: 3)
                    .clipShape(Capsule())
                VStack(alignment: .leading, spacing: HUDTheme.space1) {
                    Text("NEXT STEP")
                        .font(HUDTheme.label(.semibold))
                        .foregroundStyle(HUDTheme.textTertiary)
                        .tracking(1.2)
                    Text(nextStep.action)
                        .font(HUDTheme.body(.medium))
                        .foregroundStyle(HUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(nextStep.rationale)
                        .font(HUDTheme.label())
                        .foregroundStyle(HUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, HUDTheme.space2)
            .overlay(alignment: .top) {
                Rectangle().fill(HUDTheme.hairline).frame(height: 1)
            }
        }
    }

    private func statusAndMetrics(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: HUDTheme.space3) {
            statusChips(alignment: alignment)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: HUDTheme.space2)], spacing: HUDTheme.space2) {
                identityMetric("POWER", vehicle.currentPowerFigure?.compactLabel ?? "No dyno")
                identityMetric("SERVICE", serviceMetric)
                identityMetric("ACTIVITY", vehicle.lastActivityDate.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "No log")
            }
        }
    }

    private func statusChips(alignment: HorizontalAlignment) -> some View {
        HStack(spacing: HUDTheme.space2) {
            ForEach(statusChips, id: \.label) { chip in
                HStack(spacing: HUDTheme.space1) {
                    Circle().fill(chip.color).frame(width: 6, height: 6)
                    Text(chip.label)
                        .font(HUDTheme.label(.semibold))
                        .foregroundStyle(chip.color)
                        .tracking(0.8)
                }
                .padding(.horizontal, HUDTheme.space2)
                .padding(.vertical, HUDTheme.space1)
                .background(RoundedRectangle(cornerRadius: HUDTheme.space2).fill(HUDTheme.elevatedSurface.opacity(0.66)))
                .overlay(RoundedRectangle(cornerRadius: HUDTheme.space2).strokeBorder(chip.color.opacity(0.24), lineWidth: 1))
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private func identityMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: HUDTheme.space1) {
            Text(label)
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textTertiary)
                .tracking(1)
            Text(value)
                .font(HUDTheme.body(.medium))
                .foregroundStyle(HUDTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(HUDTheme.space2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            VStack(spacing: 0) {
                Rectangle().fill(HUDTheme.hairline).frame(height: 1)
                HUDTheme.elevatedSurface.opacity(0.34)
            }
        )
    }

    private var statusChips: [(label: String, color: Color)] {
        var chips: [(String, Color)] = []
        if vehicle.serviceStatus.isInService {
            chips.append(("OUT OF SERVICE", HUDTheme.amber))
        } else {
            switch vehicle.maintenanceDue() {
            case .overdue: chips.append(("SERVICE OVERDUE", HUDTheme.danger))
            case .dueSoon: chips.append(("SERVICE DUE SOON", HUDTheme.amber))
            case .ok: chips.append(("OPERATIONAL", HUDTheme.green))
            }
        }
        if reviewCount > 0 { chips.append(("\(reviewCount) TO REVIEW", HUDTheme.amber)) }
        return chips
    }

    private var identityState: String {
        if vehicle.serviceStatus.isInService { return "In service bay" }
        switch vehicle.maintenanceDue() {
        case .overdue: return "Service overdue"
        case .dueSoon: return "Operational · service due soon"
        case .ok: return "Operational"
        }
    }

    private var identityColor: Color {
        if vehicle.serviceStatus.isInService { return HUDTheme.amber }
        switch vehicle.maintenanceDue() {
        case .overdue: return HUDTheme.danger
        case .dueSoon: return HUDTheme.amber
        case .ok: return HUDTheme.green
        }
    }

    private var serviceMetric: String {
        if let service = vehicle.maintenance
            .map({ ($0, $0.due(currentMileage: vehicle.currentMileage)) })
            .sorted(by: { lhs, rhs in dueRank(lhs.1) > dueRank(rhs.1) })
            .first(where: { $0.1 != .ok }) {
            return service.0.name
        }
        if vehicle.serviceStatus.isInService { return "In progress" }
        return "Current"
    }

    private func dueRank(_ due: MaintenanceItem.Due) -> Int {
        switch due {
        case .overdue: return 2
        case .dueSoon: return 1
        case .ok: return 0
        }
    }

    private var accessibilitySummary: String {
        "\(vehicle.displayName), \(identityState), \(reviewCount) items to review, next step \(nextStep?.action ?? "none")"
    }
}
