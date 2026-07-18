import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// The whole garage as one polished, shareable document — rendered from the app's own cockpit
/// design system to a PDF, so the sheet reads like GarageHUD, not like exported text. It formats
/// only what's on record (power, spend, systems coverage, intent) and grades power by whether it's
/// measured — the same honesty the app holds to on screen.
public enum FleetSheetPDF {
    /// US-Letter width; height hugs the content into a single continuous page.
    @MainActor
    public static func data(for vehicles: [Vehicle], pageWidth: CGFloat = 612) -> Data? {
        let doc = FleetSheetDocument(vehicles: vehicles).frame(width: pageWidth)
        let renderer = ImageRenderer(content: doc)
        renderer.proposedSize = ProposedViewSize(width: pageWidth, height: nil)
        var result: Data?
        renderer.render { size, renderInContext in
            let mutable = NSMutableData()
            guard let consumer = CGDataConsumer(data: mutable as CFMutableData) else { return }
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            ctx.beginPDFPage(nil)
            renderInContext(ctx)
            ctx.endPDFPage()
            ctx.closePDF()
            result = mutable as Data
        }
        return result
    }
}

/// A shareable fleet sheet. Holds the vehicles and defers the (main-actor) PDF render until a share
/// destination is actually chosen, so putting one in a `ShareLink` costs nothing until it's used.
public struct SharableFleetSheet: Transferable, Sendable {
    public enum RenderError: Error { case renderFailed }

    public let fileName: String   // without extension
    public let vehicles: [Vehicle]

    public init(fileName: String = "GarageHUD Fleet Sheet", vehicles: [Vehicle]) {
        self.fileName = fileName
        self.vehicles = vehicles
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { sheet in
            // Fail loudly if the render comes back empty, so the share sheet surfaces an error
            // rather than silently handing over a 0-byte, un-openable PDF.
            guard let data = await MainActor.run(body: { FleetSheetPDF.data(for: sheet.vehicles) }),
                  !data.isEmpty else {
                throw RenderError.renderFailed
            }
            return data
        }
        .suggestedFileName { "\($0.fileName).pdf" }
    }
}

// MARK: - The document

struct FleetSheetDocument: View {
    let vehicles: [Vehicle]

    private var ordered: [Vehicle] { vehicles.sorted { $0.garageSlot < $1.garageSlot } }
    private var totalInvested: Double { vehicles.reduce(0) { $0 + $1.totalInvested } }
    private var measuredCount: Int { vehicles.filter { $0.hasMeasuredPower }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space4) {
            header
            ForEach(ordered) { FleetSheetCard(vehicle: $0) }
            footer
        }
        .padding(HUDTheme.space5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HUDTheme.background)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space3) {
            HStack(alignment: .firstTextBaseline) {
                Text("GARAGE").font(HUDTheme.title()).foregroundStyle(HUDTheme.textPrimary).tracking(2)
                Spacer()
                Text("FLEET SHEET").font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.cyan).tracking(3)
            }
            Rectangle().fill(HUDTheme.cyan.opacity(0.6)).frame(height: 2)
            HStack(spacing: HUDTheme.space5) {
                statBlock("BAYS", "\(vehicles.count)")
                statBlock("INVESTED", money(totalInvested))
                statBlock("MEASURED", "\(measuredCount) of \(vehicles.count)")
            }
        }
    }

    private func statBlock(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary).tracking(1.5)
            Text(value).font(HUDTheme.section()).foregroundStyle(HUDTheme.textPrimary)
        }
    }

    /// Only show the dot legend when a card actually carries system dots, so a fleet with no
    /// assessed builds doesn't advertise a key to nothing.
    private var showsSystemsLegend: Bool {
        vehicles.contains { (Steward.assess($0)?.subsystems.isEmpty == false) }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            if showsSystemsLegend {
                HStack(spacing: HUDTheme.space3) {
                    legendKey(HUDTheme.green, "covered")
                    legendKey(HUDTheme.amber, "planned")
                    legendKey(HUDTheme.danger, "open gap")
                    legendKey(HUDTheme.textTertiary, "not documented")
                    Spacer(minLength: 0)
                }
                Rectangle().fill(HUDTheme.hairline).frame(height: 1)
            }
            HStack {
                Text("Generated by GarageHUD").font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
                Spacer()
                Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            }
        }
        .padding(.top, HUDTheme.space2)
    }

    private func legendKey(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
        }
    }
}

// MARK: - One vehicle

struct FleetSheetCard: View {
    let vehicle: Vehicle

    private var assessment: BuildAssessment? { Steward.assess(vehicle) }
    private var progress: BuildProgress { BuildPlanner.plan(for: vehicle).progress }

    var body: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space3) {
            titleRow
            if !vehicle.engineDescription.isEmpty {
                Text(vehicle.engineDescription).font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
            }
            statsRow
            if let goal = vehicle.buildGoal, goal.isSet { goalRow(goal) }
            if let a = assessment, !a.subsystems.isEmpty { systemsRow(a) }
            if let a = assessment {
                Text(a.headline).font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HUDTheme.panelPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: HUDTheme.space2) {
                    Text(vehicle.displayName).font(HUDTheme.section()).foregroundStyle(HUDTheme.textPrimary)
                    if vehicle.serviceStatus.isInService {
                        Text("OUT OF SERVICE").font(HUDTheme.label(.semibold))
                            .foregroundStyle(HUDTheme.amber).tracking(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(HUDTheme.amber.opacity(0.5), lineWidth: 1))
                    }
                }
                Text(vehicle.subtitle.uppercased()).font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textTertiary).tracking(1)
            }
            Spacer(minLength: HUDTheme.space3)
            powerReadout
        }
    }

    @ViewBuilder
    private var powerReadout: some View {
        if let figure = vehicle.currentPowerFigure {
            let measured = figure.isMeasured
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(figure.value))").font(HUDTheme.title()).foregroundStyle(measured ? HUDTheme.cyan : HUDTheme.textPrimary)
                Text(measured ? "\(figure.unit) \(figure.qualifier)" : "\(figure.unit) est").font(HUDTheme.label())
                    .foregroundStyle(measured ? HUDTheme.cyan : HUDTheme.textTertiary)
                if let gain = vehicle.horsepowerGainedOverStock, gain >= 1 {
                    Text("+\(Int(gain)) over stock").font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                }
            }
        } else {
            Text("NOT YET MEASURED").font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary).tracking(1)
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: HUDTheme.space5) {
            if vehicle.totalInvested > 0 {
                miniStat("INVESTMENT", money(vehicle.totalInvested),
                         vehicle.investmentIsLiveFromParts ? "logged parts" : "documented")
            }
            if let base = vehicle.estimatedStockWheelHP {
                miniStat("STOCK BASELINE", "\(Int(base)) whp", vehicle.drivetrain.displayName)
            }
        }
    }

    private func miniStat(_ label: String, _ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary).tracking(1.2)
            Text(value).font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
            Text(caption).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
        }
    }

    private func goalRow(_ goal: BuildGoal) -> some View {
        HStack(alignment: .center, spacing: HUDTheme.space2) {
            Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(HUDTheme.green)
            Text(goal.summary.isEmpty ? "\(Int(goal.targetWheelHP ?? 0)) whp goal" : goal.summary)
                .font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
            Spacer(minLength: 0)
            if let frac = progress.powerFraction {
                Text("\(Int((frac * 100).rounded()))% to goal")
                    .font(HUDTheme.label(.semibold)).foregroundStyle(frac >= 1 ? HUDTheme.green : HUDTheme.cyan)
            }
        }
    }

    private func systemsRow(_ a: BuildAssessment) -> some View {
        HStack(spacing: HUDTheme.space3) {
            ForEach(a.subsystems.prefix(5)) { sub in
                HStack(spacing: 5) {
                    Circle().fill(statusColor(sub)).frame(width: 6, height: 6)
                    Text(sub.label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func statusColor(_ sub: BuildAssessment.Subsystem) -> Color {
        switch sub.status {
        case .supported: return HUDTheme.green
        case .openItem: return sub.planned ? HUDTheme.amber : HUDTheme.danger
        case .undocumented: return HUDTheme.textTertiary
        }
    }
}

private func money(_ v: Double) -> String {
    v.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}
