import Foundation

/// The pure content of one fleet-sheet card — every string the buyer-facing PDF prints for a
/// vehicle, extracted from the SwiftUI card so it is testable and covered by the honesty sweep.
/// The rendered PDF itself can't be text-swept; this model is the words, the card is the ink.
/// `FleetSheetCard` must render exclusively from this model — a string that bypasses it also
/// bypasses the sweep.
public struct FleetSheetCardModel: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let outOfService: Bool
    public let engine: String?

    /// Big number ("477") + its caption ("whp measured" / "hp est"), or `noPowerText` instead.
    public let powerValue: String?
    public let powerCaption: String?
    public let powerMeasured: Bool
    public let powerGain: String?          // "+276 over stock"
    public let noPowerText: String?        // "NOT YET MEASURED"

    public let investmentValue: String?    // "$12,345"
    public let investmentCaption: String?  // "logged parts" / "documented"
    public let stockBaselineValue: String? // "160 whp"
    public let stockBaselineCaption: String?

    public let goalText: String?           // "Reliable 450 whp street car" / "450 whp goal"
    public let goalPercent: String?        // "64% to goal"
    public let goalReached: Bool

    public let subsystems: [BuildAssessment.Subsystem]
    public let headline: String?

    public static func make(for vehicle: Vehicle) -> FleetSheetCardModel {
        let assessment = Steward.assess(vehicle)
        let progress = BuildPlanner.plan(for: vehicle).progress
        let figure = vehicle.currentPowerFigure
        let investment = vehicle.investmentFigure

        let gain: String? = {
            guard let g = vehicle.horsepowerGainedOverStock, g >= 1 else { return nil }
            return "+\(Int(g)) over stock"
        }()

        let goal = vehicle.buildGoal
        let goalText: String? = (goal?.isSet == true)
            ? (goal!.summary.isEmpty ? "\(Int(goal!.targetWheelHP ?? 0)) whp goal" : goal!.summary)
            : nil
        let fraction = (goal?.isSet == true) ? progress.powerFraction : nil

        return FleetSheetCardModel(
            title: vehicle.displayName,
            subtitle: vehicle.subtitle.uppercased(),
            outOfService: vehicle.serviceStatus.isInService,
            engine: vehicle.engineDescription.isEmpty ? nil : vehicle.engineDescription,
            powerValue: figure.map { "\(Int($0.value))" },
            powerCaption: figure.map { $0.isMeasured ? "\($0.unit) \($0.qualifier)" : "\($0.unit) est" },
            powerMeasured: figure?.isMeasured ?? false,
            powerGain: gain,
            noPowerText: figure == nil ? "NOT YET MEASURED" : nil,
            investmentValue: investment.map { money($0.total) },
            investmentCaption: investment?.sourceShort,
            stockBaselineValue: vehicle.estimatedStockWheelHP.map { "\(Int($0)) whp" },
            stockBaselineCaption: vehicle.estimatedStockWheelHP != nil ? vehicle.drivetrain.displayName : nil,
            goalText: goalText,
            goalPercent: fraction.map { "\(Int(($0 * 100).rounded()))% to goal" },
            goalReached: (fraction ?? 0) >= 1,
            subsystems: assessment.map { Array($0.subsystems.prefix(5)) } ?? [],
            headline: assessment?.headline)
    }

    /// Every printed string in reading order — what the honesty sweep checks. Labels are kept
    /// adjacent to their values so estimate markers ("STOCK BASELINE", "goal") share a window
    /// with the figures they qualify, exactly as they share the eye's window on the page.
    public var sweepText: String {
        var parts: [String] = [title, subtitle]
        if outOfService { parts.append("OUT OF SERVICE") }
        if let engine { parts.append(engine) }
        if let powerValue, let powerCaption { parts.append("\(powerValue) \(powerCaption)") }
        if let powerGain { parts.append(powerGain) }
        if let noPowerText { parts.append(noPowerText) }
        if let investmentValue, let investmentCaption { parts.append("INVESTMENT \(investmentValue) \(investmentCaption)") }
        if let stockBaselineValue { parts.append("STOCK BASELINE \(stockBaselineValue) (\(stockBaselineCaption ?? ""))") }
        if let goalText { parts.append(goalText) }
        if let goalPercent { parts.append(goalPercent) }
        for sub in subsystems {
            let status = sub.status == .supported ? "covered" : (sub.status == .openItem ? "open gap" : "not documented")
            parts.append("\(sub.label): \(status)\(sub.planned ? " (planned)" : "")")
        }
        if let headline { parts.append(headline) }
        return parts.joined(separator: " · ")
    }
}

private func money(_ v: Double) -> String {
    v.formatted(.currency(code: "USD").precision(.fractionLength(0)))
}
