import Foundation

/// The vehicle biography — the whole story, exportable. Where the build sheet is the car's
/// spec-card, the biography is its life: the full timeline, every service with its cost, the
/// performance history graded by evidence, the ownership money facts kept honestly separate,
/// and a provenance appendix explaining where each headline figure comes from. "The story is
/// the product" (Constitution) — this is the story, preserved for a sale, an insurance claim,
/// a valuation, or a legacy.
///
/// Formats only what's on record; invents nothing. Pure and textual, covered by the honesty
/// sweep like every other surface that prints numbers.
public enum BiographyExporter {

    public static func text(for vehicle: Vehicle, context: StewardContext = .live) -> String {
        var out: [String] = []
        func line(_ s: String = "") { out.append(s) }
        func header(_ s: String) { line(); line(s.uppercased()); line(String(repeating: "-", count: s.count)) }

        // Identity
        line("VEHICLE BIOGRAPHY")
        line(vehicle.subtitle.uppercased() + (vehicle.nickname.isEmpty ? "" : " · \"\(vehicle.nickname)\""))
        if !vehicle.engineDescription.isEmpty { line(vehicle.engineDescription) }
        if vehicle.drivetrain != .unknown { line("Drivetrain: \(vehicle.drivetrain.displayName)") }
        if vehicle.serviceStatus.isInService {
            let reason = vehicle.serviceStatus.reason.isEmpty ? "" : " — \(vehicle.serviceStatus.reason)"
            line("Status: Out of service\(reason)")
        }
        if let miles = vehicle.currentMileage {
            line("Odometer: \(miles.formatted(.number.grouping(.automatic))) mi (recorded)")
        }

        // Power & performance — graded by evidence.
        header("Power")
        if let figure = vehicle.currentPowerFigure {
            line(figure.labeled)
        } else {
            line("No power figure on record")
        }
        let performances = vehicle.performanceRecords.sorted { $0.date > $1.date }
        if !performances.isEmpty {
            line()
            line("Performance record:")
            for record in performances {
                let place = record.location.isEmpty ? "" : " — \(record.location)"
                line("  \(short(record.date)) — \(record.summary)\(place)")
            }
        }

        // The build.
        let installed = vehicle.parts.filter { $0.status == .installed }
        if !installed.isEmpty {
            header("Build (\(installed.count) installed parts)")
            for category in PartCategory.allCases {
                let inCat = installed.filter { $0.category == category }
                guard !inCat.isEmpty else { continue }
                line(category.rawValue + ":")
                for part in inCat {
                    let cost = part.cost.map { " — \(dollars($0))" } ?? ""
                    let dated = part.installDate.map { " (installed \(short($0)))" } ?? ""
                    line("  - \(part.name)\(cost)\(dated)")
                }
            }
        }
        let planned = vehicle.plannedParts
        if !planned.isEmpty {
            header("Planned (not yet installed)")
            for part in planned {
                let cost = part.cost.map { " — \(dollars($0)) planned" } ?? ""
                line("  - \(part.name) (\(part.category.rawValue))\(cost)")
            }
        }
        if let a = Steward.assess(vehicle) {
            header("Build assessment")
            line(a.powerSummary)
            line(a.headline)
        }

        // Service record — the maintenance half of the story, with costs.
        let services = vehicle.serviceLog
        if !services.isEmpty {
            header("Service record (\(services.count))")
            for event in services {
                let name = event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: "")
                let cost = event.cost.map { " — \(dollars($0))" } ?? ""
                line("  \(short(event.date)) — \(name)\(cost)")
            }
            if vehicle.serviceSpend > 0 {
                line("Total recorded service spend: \(dollars(vehicle.serviceSpend))")
            }
        }

        // The story — the full timeline, newest first.
        let events = vehicle.buildEvents.sorted { $0.date > $1.date }
        if !events.isEmpty {
            header("Timeline (\(events.count) events)")
            for event in events {
                let odo = event.mileage.map { " @ \($0.formatted(.number.grouping(.automatic))) mi" } ?? ""
                line("  \(short(event.date)) — \(event.title)\(odo)")
            }
        }

        // Ownership — three money facts, never conflated.
        header("Ownership")
        if let paid = vehicle.purchasePrice, paid > 0 { line("Purchase price: \(dollars(paid))") }
        if let investment = vehicle.investmentFigure {
            line("Build investment: \(dollars(investment.total)) \(investment.sheetPhrase)")
        }
        if vehicle.serviceSpend > 0 { line("Maintenance spend: \(dollars(vehicle.serviceSpend))") }

        // Provenance appendix — every headline figure answers for itself.
        let provenances = [ProvenanceBuilder.power(for: vehicle),
                           ProvenanceBuilder.investment(for: vehicle),
                           ProvenanceBuilder.odometer(for: vehicle)].compactMap { $0 }
        if !provenances.isEmpty {
            header("Where these numbers come from")
            for p in provenances {
                line(p.headline)
                for evidence in p.lines { line("  - \(evidence)") }
                line()
            }
        }

        line("Generated by GarageHUD — every figure graded by the evidence behind it.")
        return out.joined(separator: "\n")
    }

    /// The biography as a named, shareable file.
    public static func file(for vehicle: Vehicle, context: StewardContext = .live) -> SharableTextFile {
        SharableTextFile(fileName: "\(vehicle.displayName) biography",
                         text: text(for: vehicle, context: context))
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    private static func dollars(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
}
