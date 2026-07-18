import Foundation

/// The tap-through answer to "why should I trust this number?" — where a headline figure came
/// from, in the Steward's evidence-first voice. The Constitution demands "never pretend
/// certainty, always explain"; the model has carried provenance all along, and this surfaces it
/// at the figure itself instead of making the owner reverse-engineer the math.
///
/// Pure and textual, so it is testable and covered by the honesty sweep like every other
/// surface that prints numbers.
public struct FigureProvenance: Equatable, Sendable {
    /// The figure being explained, with its honest label — e.g. "477 whp (measured)".
    public let headline: String
    /// Evidence lines, most direct first. Each line stands alone.
    public let lines: [String]

    /// All text, for the honesty sweep.
    public var sweepText: String { ([headline] + lines).joined(separator: " · ") }
}

public enum ProvenanceBuilder {

    /// Where the power figure comes from: the measurement and its date, the factory rating it
    /// stands on, the derived stock-wheel baseline — and, honestly, whether hardware has
    /// changed since the measurement.
    public static func power(for vehicle: Vehicle) -> FigureProvenance? {
        guard let figure = vehicle.currentPowerFigure else { return nil }
        var lines: [String] = []

        if let dyno = vehicle.latestMeasuredDyno, let hp = dyno.wheelHorsepower {
            let place = dyno.location.isEmpty ? "" : " at \(dyno.location)"
            lines.append("Measured \(Int(hp)) whp on the dyno \(short(dyno.date))\(place).")
            if let change = vehicle.latestInstall(inAny: [.engine, .forcedInduction, .fueling, .cooling, .exhaust, .electronics]),
               change.date > dyno.date {
                lines.append("\(change.part.name) was installed \(short(change.date)) — after this dyno, so the figure may not reflect the car now.")
            }
            if let factory = vehicle.factoryHorsepower {
                lines.append("Factory rating: \(Int(factory)) hp (\(vehicle.factoryPowerBasis.describes)).")
            }
        } else {
            lines.append("Factory rating (\(vehicle.factoryPowerBasis.describes)) — no measured dyno figure on record.")
            if vehicle.performanceRecords.contains(where: { $0.type == .dyno }) {
                lines.append("A dyno session is logged but carries no measured figure.")
            }
        }

        if let baseline = vehicle.estimatedStockWheelHP, vehicle.factoryPowerBasis != .measuredWheel {
            let loss = vehicle.stockWheelBaselineIsAssumed
                ? "assumed ~\(Int(Drivetrain.unknown.typicalLossFraction * 100))% driveline loss (drivetrain unspecified)"
                : "~\(Int(vehicle.drivetrain.typicalLossFraction * 100))% typical \(vehicle.drivetrain.label) driveline loss"
            lines.append("Estimated stock wheel baseline: \(Int(baseline)) whp — factory rating minus \(loss).")
        }

        return FigureProvenance(headline: figure.labeled, lines: lines)
    }

    /// Where "total invested" comes from: the max-of rule stated plainly, with both inputs.
    public static func investment(for vehicle: Vehicle) -> FigureProvenance? {
        guard let investment = vehicle.investmentFigure else { return nil }
        var lines: [String] = []

        let pricedCount = vehicle.parts.filter { $0.status == .installed && ($0.cost ?? 0) > 0 }.count
        let itemized = vehicle.itemizedPartsCost
        if itemized > 0 {
            lines.append("Itemized: \(dollars(itemized)) across \(pricedCount) priced installed part\(pricedCount == 1 ? "" : "s").")
        }
        if let documented = vehicle.documentedTotalInvestment, documented > 0 {
            lines.append("Documented build-sheet total: \(dollars(documented)).")
        }
        lines.append(investment.isLiveFromParts
            ? "The larger figure is the parts sum, so it leads — editing a part price moves it."
            : "The documented total leads while it exceeds the priced parts — it covers spend the parts don't yet (unpriced parts, labor, tax).")
        if let priced = investment.pricedSoFar {
            lines.append("\(dollars(priced)) of it is priced in parts so far.")
        }
        if vehicle.plannedSpend > 0 {
            lines.append("Planned (wishlist) spend of \(dollars(vehicle.plannedSpend)) is not included — planned money isn't spend.")
        }

        return FigureProvenance(headline: "\(dollars(investment.total)) \(investment.sheetPhrase)", lines: lines)
    }

    /// Where the odometer figure comes from: the event that recorded it, the learned rate —
    /// and, honestly, whether the record disagrees with itself.
    public static func odometer(for vehicle: Vehicle) -> FigureProvenance? {
        guard let miles = vehicle.currentMileage else { return nil }
        var lines: [String] = []

        let readings = vehicle.buildEvents
            .compactMap { e in e.mileage.map { (event: e, miles: $0) } }
            .sorted { $0.event.date > $1.event.date }
        if let latest = readings.first {
            lines.append("From \"\(latest.event.title)\", \(short(latest.event.date)).")
        }
        let count = readings.count
        if let rate = vehicle.milesPerDay {
            lines.append("Driving rate: ~\(Int(rate.rounded())) mi/day, learned from \(count) dated reading\(count == 1 ? "" : "s").")
        } else if count == 1 {
            lines.append("One reading so far — a second, on a different day, lets the Steward learn your driving rate.")
        }
        let ordered = readings.reversed()
        if zip(ordered, ordered.dropFirst()).contains(where: { $1.miles < $0.miles }) {
            lines.append("Heads up: the odometer record disagrees with itself (a later entry is lower) — projections lean on these readings.")
        }

        return FigureProvenance(
            headline: "\(miles.formatted(.number.grouping(.automatic))) mi (recorded)",
            lines: lines)
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    private static func dollars(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
