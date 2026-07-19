import Foundation

/// Assembles a compact, factual "record" of a vehicle for the on-device LLM Steward to reason over.
/// This is the honesty pivot for the conversational layer: the model is told to answer ONLY from
/// this record, so it can talk freely without inventing horsepower, parts, or history. It folds in
/// the reasoning engine's own observations (with their confidence bands), so the LLM inherits the
/// Steward's calibrated judgment instead of re-deriving it. Pure and framework-free so it's fully
/// testable without the model on hand.
public enum StewardGrounding {

    /// The system instructions — the Steward's character and its hard honesty rules.
    public static let instructions = """
    You are the Fleet Steward in GarageHUD, an evidence-led assistant for a car enthusiast's build.

    Rules you must not break:
    - Answer ONLY from the VEHICLE RECORD provided in the prompt. Never invent numbers, parts, dates, \
    or history. If a fact isn't in the record, say it isn't recorded and suggest what to log.
    - Respect stated confidence. Facts may carry a band: Confirmed, Strong, Moderate, Weak, or \
    Insufficient. Never state a Weak or estimated figure as certain.
    - Report figures exactly as recorded. Do NOT add, subtract, or otherwise combine two recorded \
    values to produce a new number. Many figures in the record are DERIVED from others and already \
    contain them — summing them double-counts and produces a number the owner never measured. If a \
    total the owner asks for is not present in the record, say it isn't recorded rather than \
    computing one.
    - You may reason about implications (for example, whether fueling supports a boost increase), but \
    frame any inference as an inference, not a measured fact.
    - Never give a safety guarantee about a mechanical modification, and never claim to know AFR, \
    ignition timing, or knock — standard data cannot prove those.

    Voice: concise and direct. Lead with the answer in one sentence, then at most a short supporting \
    line. No filler, no hype, no restating the question. Speak like a knowledgeable shop steward.
    """

    /// A plain-text record of everything known about the car, for the model's context.
    public static func record(for vehicle: Vehicle, context: StewardContext = .live) -> String {
        var lines: [String] = []
        func section(_ title: String) { lines.append(""); lines.append("[\(title)]") }
        func fact(_ label: String, _ value: String?) { if let value, !value.isEmpty { lines.append("- \(label): \(value)") } }

        lines.append("VEHICLE RECORD")
        section("Identity")
        fact("Name", vehicle.displayName)
        fact("Vehicle", "\(vehicle.year) \(vehicle.make) \(vehicle.model)\(vehicle.trim.isEmpty ? "" : " " + vehicle.trim)")
        fact("Drivetrain", vehicle.drivetrain == .unknown ? nil : vehicle.drivetrain.displayName)
        fact("Engine", vehicle.engineDescription.isEmpty ? nil : vehicle.engineDescription)
        fact("Induction", vehicle.hasFactoryForcedInduction
            ? "factory turbocharged/supercharged (the stock charger is part of the car, not a modification)"
            : nil)
        fact("Odometer", vehicle.currentMileage.map { "\($0.formatted(.number.grouping(.automatic))) mi" })
        if vehicle.serviceStatus.isInService {
            fact("Status", "OUT OF SERVICE" + (vehicle.serviceStatus.reason.isEmpty ? "" : " — \(vehicle.serviceStatus.reason)"))
        }

        section("Power")
        if let dyno = vehicle.latestMeasuredDyno, let hp = dyno.wheelHorsepower {
            fact("Measured power", "\(Int(hp)) whp on the dyno \(short(dyno.date)) [Strong evidence] "
                 + "— this IS the car's current total power at the wheels")
        } else if let f = vehicle.factoryHorsepower {
            // Distinguish "no dyno logged" from "a dyno is logged but carries no figure" — the
            // owner can see that session in the timeline, so denying it would be a false claim
            // about the record itself.
            let dynoNote = vehicle.performanceRecords.contains { $0.type == .dyno }
                ? "a dyno session is logged but carries no measured figure"
                : "no dyno logged"
            fact("Power", "\(Int(f)) hp factory rating, \(dynoNote) [Weak — estimate only]")
        }
        // The gain is DERIVED from the measured figure (measured − stock baseline), so it is already
        // contained in it. Stated as a bare sibling fact it invited the LLM to sum the two and report
        // a total the owner never measured (W-061, field-found 2026-07-19). Name the containment.
        if let gained = vehicle.horsepowerGainedOverStock {
            if let measured = vehicle.measuredWheelHorsepower {
                fact("Gained over stock", "~\(Int(gained)) whp of that \(Int(measured)) whp is gain over "
                     + "the stock baseline — already included in the \(Int(measured)), NOT additional to "
                     + "it. Do not add these together. [estimate]")
            } else {
                fact("Gained over stock", "~\(Int(gained)) whp [estimate]")
            }
        }
        fact("Power-to-weight", vehicle.powerToWeight.map {
            String(format: "%.1f lb/hp", $0) + (vehicle.hasMeasuredPower ? "" : " [from factory rating]")
        })

        section("Investment")
        if let investment = vehicle.investmentFigure {
            fact("Total invested", "\(dollars(investment.total)) [\(investment.sourceLong)] "
                 + "— this IS the whole build investment figure")
            // Both of the following are other VIEWS of the same money, never extra money on top of
            // the total. Same additive trap as power (W-061).
            fact("Build-sheet total (lower than logged parts)", investment.documentedReconcile.map {
                "\(dollars($0)) — a different accounting of the same spend, NOT additional to the total"
            })
            fact("Priced in parts so far", investment.pricedSoFar.map {
                "\(dollars($0)) — the portion of the total already priced out in parts, NOT additional to it"
            })
            fact("Cost per wheel-hp gained", vehicle.costPerHpGroundingText)
        }
        fact("Installed parts", vehicle.installedPartsCount > 0 ? "\(vehicle.installedPartsCount)" : nil)
        fact("Planned (wishlist) parts", vehicle.wishlistPartsCount > 0 ? "\(vehicle.wishlistPartsCount), ~\(dollars(vehicle.plannedSpend)) planned" : nil)

        let modifiedSystems = vehicle.spendByCategory.filter { $0.total > 0 }.map { "\($0.category.rawValue) (\(dollars($0.total)))" }
        if !modifiedSystems.isEmpty { fact("Spend by system (installed parts)", modifiedSystems.joined(separator: ", ")) }
        let stock = vehicle.confirmedStockSystems.map(\.rawValue).sorted()
        if !stock.isEmpty { fact("Confirmed factory-stock", stock.joined(separator: ", ")) }

        let due = vehicle.maintenance.compactMap { item -> String? in
            switch item.due(now: context.now, calendar: context.calendar, currentMileage: vehicle.currentMileage) {
            case .overdue: return "\(item.name) OVERDUE"
            case .dueSoon: return "\(item.name) due soon"
            case .ok: return nil
            }
        }
        if !due.isEmpty { section("Maintenance"); due.forEach { lines.append("- \($0)") } }

        let observations = Steward.observe(vehicle, context: context)
        if !observations.isEmpty {
            section("Steward observations (already reasoned, with confidence)")
            for o in observations.prefix(6) {
                lines.append("- \(o.statement) [\(o.confidence.label)] — \(o.evidence)")
            }
        }

        fact("Last logged activity", vehicle.lastActivityDate.map { short($0) })
        return lines.joined(separator: "\n")
    }

    /// The full prompt: record + the owner's question.
    public static func prompt(question: String, vehicle: Vehicle, context: StewardContext = .live) -> String {
        """
        \(record(for: vehicle, context: context))

        The owner asks: "\(question.trimmingCharacters(in: .whitespacesAndNewlines))"
        Answer as the Steward, from the record above.
        """
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    private static func dollars(_ v: Double) -> String { v.formatted(.currency(code: "USD")) }
}

private extension Vehicle {
    var costPerHpGroundingText: String? {
        guard let costPerHp = costPerHorsepowerGained else { return nil }
        return "~\(costPerHp.formatted(.currency(code: "USD"))) per wheel-hp [Moderate — wheel-estimate, not dyno-corrected]"
    }
}
