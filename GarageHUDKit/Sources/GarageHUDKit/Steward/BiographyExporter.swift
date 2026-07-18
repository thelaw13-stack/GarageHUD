import Foundation

/// The vehicle biography's content — the whole story as structured sections, so the text export
/// and the styled PDF print the *same words* by construction. One model, two inks; a string that
/// bypasses the model bypasses both renderers and the honesty sweep, so don't.
public struct BiographyModel: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public let title: String
        public let lines: [String]
    }
    /// Identity block above the first section (name, engine, status, odometer).
    public let headerLines: [String]
    public let sections: [Section]
    public let footer: String
}

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

    public static func model(for vehicle: Vehicle, context: StewardContext = .live) -> BiographyModel {
        var header: [String] = []
        header.append("VEHICLE BIOGRAPHY")
        header.append(vehicle.subtitle.uppercased() + (vehicle.nickname.isEmpty ? "" : " · \"\(vehicle.nickname)\""))
        if !vehicle.engineDescription.isEmpty { header.append(vehicle.engineDescription) }
        if vehicle.drivetrain != .unknown { header.append("Drivetrain: \(vehicle.drivetrain.displayName)") }
        if vehicle.serviceStatus.isInService {
            let reason = vehicle.serviceStatus.reason.isEmpty ? "" : " — \(vehicle.serviceStatus.reason)"
            header.append("Status: Out of service\(reason)")
        }
        if let miles = vehicle.currentMileage {
            header.append("Odometer: \(miles.formatted(.number.grouping(.automatic))) mi (recorded)")
        }

        var sections: [BiographyModel.Section] = []
        func section(_ title: String, _ lines: [String]) {
            if !lines.isEmpty { sections.append(.init(title: title, lines: lines)) }
        }

        // Power & performance — graded by evidence.
        var power: [String] = [vehicle.currentPowerFigure?.labeled ?? "No power figure on record"]
        let performances = vehicle.performanceRecords.sorted { $0.date > $1.date }
        if !performances.isEmpty {
            power.append("Performance record:")
            for record in performances {
                let place = record.location.isEmpty ? "" : " — \(record.location)"
                power.append("  \(short(record.date)) — \(record.summary)\(place)")
            }
        }
        section("Power", power)

        // The build.
        let installed = vehicle.parts.filter { $0.status == .installed }
        var build: [String] = []
        for category in PartCategory.allCases {
            let inCat = installed.filter { $0.category == category }
            guard !inCat.isEmpty else { continue }
            build.append(category.rawValue + ":")
            for part in inCat {
                let cost = part.cost.map { " — \(dollars($0))" } ?? ""
                let dated = part.installDate.map { " (installed \(short($0)))" } ?? ""
                build.append("  - \(part.name)\(cost)\(dated)")
            }
        }
        section("Build (\(installed.count) installed parts)", build)

        let planned = vehicle.plannedParts
        section("Planned (not yet installed)", planned.map { part in
            let cost = part.cost.map { " — \(dollars($0)) planned" } ?? ""
            return "  - \(part.name) (\(part.category.rawValue))\(cost)"
        })

        if let a = Steward.assess(vehicle) {
            section("Build assessment", [a.powerSummary, a.headline])
        }

        // Service record — the maintenance half of the story, with costs.
        let services = vehicle.serviceLog
        if !services.isEmpty {
            var lines = services.map { event -> String in
                let name = event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: "")
                let cost = event.cost.map { " — \(dollars($0))" } ?? ""
                return "  \(short(event.date)) — \(name)\(cost)"
            }
            if vehicle.serviceSpend > 0 {
                lines.append("Total recorded service spend: \(dollars(vehicle.serviceSpend))")
            }
            section("Service record (\(services.count))", lines)
        }

        // The story — the full timeline, newest first.
        let events = vehicle.buildEvents.sorted { $0.date > $1.date }
        section("Timeline (\(events.count) events)", events.map { event in
            let odo = event.mileage.map { " @ \($0.formatted(.number.grouping(.automatic))) mi" } ?? ""
            return "  \(short(event.date)) — \(event.title)\(odo)"
        })

        // Ownership — three money facts, never conflated.
        var ownership: [String] = []
        if let paid = vehicle.purchasePrice, paid > 0 { ownership.append("Purchase price: \(dollars(paid))") }
        if let investment = vehicle.investmentFigure {
            ownership.append("Build investment: \(dollars(investment.total)) \(investment.sheetPhrase)")
        }
        if vehicle.serviceSpend > 0 { ownership.append("Maintenance spend: \(dollars(vehicle.serviceSpend))") }
        section("Ownership", ownership)

        // Provenance appendix — every headline figure answers for itself.
        let provenances = [ProvenanceBuilder.power(for: vehicle),
                           ProvenanceBuilder.investment(for: vehicle),
                           ProvenanceBuilder.odometer(for: vehicle)].compactMap { $0 }
        if !provenances.isEmpty {
            var lines: [String] = []
            for p in provenances {
                lines.append(p.headline)
                lines.append(contentsOf: p.lines.map { "  - \($0)" })
            }
            section("Where these numbers come from", lines)
        }

        return BiographyModel(
            headerLines: header,
            sections: sections,
            footer: "Generated by GarageHUD — every figure graded by the evidence behind it.")
    }

    public static func text(for vehicle: Vehicle, context: StewardContext = .live) -> String {
        let model = model(for: vehicle, context: context)
        var out: [String] = model.headerLines
        for section in model.sections {
            out.append("")
            out.append(section.title.uppercased())
            out.append(String(repeating: "-", count: section.title.count))
            out.append(contentsOf: section.lines)
        }
        out.append("")
        out.append(model.footer)
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
