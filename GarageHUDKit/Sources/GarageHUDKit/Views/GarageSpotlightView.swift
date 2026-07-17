import SwiftUI

/// One image-led command surface for the vehicle currently staged on the garage overview.
/// The photograph owns the visual moment; operational facts stay in a separate, stable rail.
struct GarageSpotlightView: View {
    var vehicle: Vehicle
    var onOpen: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var image: PlatformImage?
    @State private var loadedFilename: String?

    private var readiness: TuneReadiness { Steward.tuneReadiness(vehicle) }
    private var nextStep: NextStep? { Steward.nextStep(vehicle) }
    private var latestPull: PullReport? {
        vehicle.pullReports.max(by: { $0.endedAt < $1.endedAt })
    }

    var body: some View {
        VStack(spacing: 0) {
            imageStage
            instrumentRail
        }
        .frame(maxWidth: .infinity)
        .background(HUDTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(accessibilitySummary)
        .task(id: vehicle.heroPhoto?.filename) { await loadImage() }
    }

    private var imageStage: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                photo
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                LinearGradient(
                    colors: [.clear, HUDTheme.background.opacity(0.18), HUDTheme.background.opacity(0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [HUDTheme.background.opacity(0.82), .clear],
                    startPoint: .leading,
                    endPoint: .center
                )

                VStack(alignment: .leading, spacing: HUDTheme.space2) {
                    HStack(spacing: HUDTheme.space2) {
                        Circle().fill(identityColor).frame(width: 8, height: 8)
                        Text(identityState.uppercased())
                            .font(HUDTheme.label(.semibold))
                            .foregroundStyle(identityColor)
                            .tracking(1.2)
                    }
                    Text(vehicle.displayName.uppercased())
                        .font(HUDTheme.title())
                        .foregroundStyle(HUDTheme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Text(vehicle.subtitle)
                        .font(HUDTheme.body(.medium))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(2)
                }
                .padding(HUDTheme.space4)
                .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 620, alignment: .leading)

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(HUDTheme.textPrimary)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(HUDTheme.background.opacity(0.72)))
                            .overlay(Circle().strokeBorder(HUDTheme.hairline, lineWidth: 1))
                            .accessibilityHidden(true)
                    }
                    Spacer()
                }
                .padding(HUDTheme.space3)
            }
        }
        .frame(height: horizontalSizeClass == .compact ? 218 : 290)
    }

    @ViewBuilder
    private var photo: some View {
        if let image {
            #if canImport(AppKit)
            Image(nsImage: image).resizable().scaledToFill()
            #else
            Image(uiImage: image).resizable().scaledToFill()
            #endif
        } else {
            VehicleVisualFallback(vehicle: vehicle, style: .hero)
        }
    }

    private var instrumentRail: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: horizontalSizeClass == .compact ? 132 : 170), spacing: 0)],
            spacing: 0
        ) {
            railFact("TUNE STATE", readiness.state.label.uppercased(), readiness.headline, readinessColor)
            if let latestPull {
                railFact(
                    "LAST PULL",
                    pullState(latestPull),
                    latestPull.onTargetFraction.map { "\(Int(($0 * 100).rounded()))% target fit · \(latestPull.confidence.label.lowercased())" }
                        ?? "\(Int(latestPull.rpmStart))-\(Int(latestPull.rpmPeak)) rpm · \(latestPull.confidence.label.lowercased())",
                    pullColor(latestPull)
                )
            } else {
                railFact("LAST PULL", "NO RUN", "Live session not banked", HUDTheme.textSecondary)
            }
            railFact(
                "POWER",
                vehicle.currentHorsepowerEstimate.map { "\(Int($0)) WHP" } ?? "NO DYNO",
                vehicle.latestPerformance?.summary ?? "No measured baseline",
                // On a torn-down car, power isn't the story — dim it to plain white so it stops
                // out-competing the amber OUT OF SERVICE / red TUNE STATE for the eye (DD-001 F2).
                // Cyan stays reserved for when the car is running and power is the live headline.
                vehicle.serviceStatus.isInService ? HUDTheme.textPrimary : HUDTheme.cyan
            )
            railFact(
                "NEXT ACTION",
                nextStep == nil ? "CURRENT" : "OPEN",
                nextStep?.action ?? "No immediate action surfaced",
                nextStep == nil ? HUDTheme.green : HUDTheme.amber
            )
        }
        .background(HUDTheme.panelBackground)
    }

    private func railFact(_ label: String, _ value: String, _ detail: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textTertiary)
                .tracking(1)
            Text(value)
                .font(HUDTheme.body(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(detail)
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(HUDTheme.space3)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .overlay(alignment: .leading) { Rectangle().fill(HUDTheme.hairline).frame(width: 1) }
        .overlay(alignment: .top) { Rectangle().fill(HUDTheme.hairline).frame(height: 1) }
    }

    private var identityState: String {
        if vehicle.serviceStatus.isInService { return "Out of service" }
        switch vehicle.maintenanceDue() {
        case .overdue: return "Service overdue"
        case .dueSoon: return "Service due soon"
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

    private var readinessColor: Color {
        switch readiness.state {
        case .ready: return HUDTheme.green
        case .verify: return HUDTheme.amber
        case .hold: return HUDTheme.danger
        }
    }

    private func pullState(_ pull: PullReport) -> String {
        if pull.boostBreachedCeiling { return "STOP" }
        if (pull.overTargetFraction ?? 0) >= 0.5 || (pull.underTargetFraction ?? 0) >= 0.5 { return "REVIEW" }
        return pull.onTargetFraction == nil ? "CAPTURED" : "CLEAR"
    }

    private func pullColor(_ pull: PullReport) -> Color {
        switch pullState(pull) {
        case "STOP": return HUDTheme.danger
        case "REVIEW": return HUDTheme.amber
        case "CLEAR": return HUDTheme.green
        default: return HUDTheme.cyan
        }
    }

    private var accessibilitySummary: String {
        "Active bay, \(vehicle.displayName), \(identityState), tune \(readiness.state.label), \(nextStep?.action ?? "no immediate action")"
    }

    private func loadImage() async {
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
}
