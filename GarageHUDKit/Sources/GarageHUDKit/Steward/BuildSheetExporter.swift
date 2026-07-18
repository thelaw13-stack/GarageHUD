import Foundation

/// Renders a vehicle's recorded build into a clean, shareable plain-text build sheet — the
/// Constitution's "vehicle biography, exportable". It only formats what's on record (parts,
/// spend, measured power, timeline, and the Steward's coherence read); it invents nothing.
public enum BuildSheetExporter {

    public static func text(for vehicle: Vehicle, context: StewardContext = .live) -> String {
        var out: [String] = []
        func line(_ s: String = "") { out.append(s) }
        func header(_ s: String) { line(); line(s.uppercased()) }

        // Identity
        line(vehicle.subtitle.uppercased() + (vehicle.nickname.isEmpty ? "" : " · \"\(vehicle.nickname)\""))
        if vehicle.serviceStatus.isInService {
            let reason = vehicle.serviceStatus.reason.isEmpty ? "" : " — \(vehicle.serviceStatus.reason)"
            line("Status: Out of service\(reason)")
        }
        if !vehicle.engineDescription.isEmpty { line(vehicle.engineDescription) }

        // Power
        header("Power")
        if let figure = vehicle.currentPowerFigure {
            line(figure.labeled)
            if let gained = vehicle.horsepowerGainedOverStock, let base = vehicle.estimatedStockWheelHP {
                line("+\(Int(gained)) whp over ~\(Int(base)) whp estimated stock (\(vehicle.drivetrain.displayName))")
            }
        } else {
            line("Not yet measured")
        }

        // Investment
        if let investment = vehicle.investmentFigure {
            header("Investment")
            line("\(dollars(investment.total)) \(investment.sheetPhrase)")
            if let doc = investment.documentedReconcile {
                line("(build sheet noted \(dollars(doc)); priced parts sum higher)")
            } else if let priced = investment.pricedSoFar {
                line("(\(dollars(priced)) of it priced in parts so far)")
            }
        }

        // Installed parts by system
        let installed = vehicle.parts.filter { $0.status == .installed }
        if !installed.isEmpty {
            header("Installed parts (\(installed.count))")
            for category in PartCategory.allCases {
                let inCat = installed.filter { $0.category == category }
                guard !inCat.isEmpty else { continue }
                line(category.rawValue + ":")
                for part in inCat {
                    let cost = part.cost.map { " — \(dollars($0))" } ?? ""
                    line("  - \(part.name)\(cost)")
                }
            }
        }

        // Planned upgrades
        let planned = vehicle.plannedParts
        if !planned.isEmpty {
            header("Planned")
            for part in planned {
                let cost = part.cost.map { " — \(dollars($0))" } ?? ""
                line("  - \(part.name) (\(part.category.rawValue))\(cost)")
            }
        }

        // Steward assessment
        if let a = Steward.assess(vehicle) {
            header("Build assessment")
            line(a.headline)
            for sub in a.subsystems {
                let status = sub.status == .supported ? "covered" : (sub.status == .openItem ? "open item" : "not documented")
                line("  \(sub.label): \(status)\(sub.planned ? " (planned)" : "")")
            }
        }

        // Maintenance schedule
        if !vehicle.maintenance.isEmpty {
            header("Maintenance")
            for item in vehicle.maintenance {
                let odo = vehicle.currentMileage
                let milesRemaining = item.milesUntilDue(currentMileage: odo)
                let status: String
                switch item.due(now: context.now, calendar: context.calendar, currentMileage: odo) {
                case .overdue: status = "OVERDUE"
                case .dueSoon: status = "due soon"
                case .ok: status = "ok"
                }
                var interval = "every \(item.intervalMonths) mo"
                if let miles = item.intervalMiles { interval += " / \(miles) mi" }
                // Name the leg that's actually driving the state — "OVERDUE … due <next year>"
                // (time date shown while the mileage interval is what's blown) reads as a
                // contradiction on a document a buyer may see.
                let dueText: String
                if let m = milesRemaining, m <= 0, let target = item.dueMileage {
                    dueText = "\((-m).formatted(.number.grouping(.automatic))) mi past the \(target.formatted(.number.grouping(.automatic))) mi mark"
                } else if let m = milesRemaining, m <= 500 {
                    dueText = "due in \(m.formatted(.number.grouping(.automatic))) mi"
                } else {
                    dueText = "due \(short(item.dueDate(context.calendar)))"
                }
                line("  \(item.name): \(status) — \(interval), \(dueText)")
            }
        }

        // Service history (completed services)
        let services = vehicle.serviceLog.prefix(8)
        if !services.isEmpty {
            header("Service History")
            for event in services {
                let name = event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: "")
                line("  \(short(event.date)) — \(name)")
            }
        }

        // Timeline highlights
        let events = vehicle.buildEvents.sorted { $0.date > $1.date }.prefix(6)
        if !events.isEmpty {
            header("Timeline")
            for event in events {
                line("  \(short(event.date)) — \(event.title)")
            }
        }

        line()
        line("Generated by GarageHUD")
        return out.joined(separator: "\n")
    }

    /// The build sheet as a named, shareable file — so "Save to Files" writes a real `.txt` instead
    /// of falling back to stale transfer-buffer data.
    public static func file(for vehicle: Vehicle, context: StewardContext = .live) -> SharableTextFile {
        SharableTextFile(fileName: "\(vehicle.displayName) build sheet",
                         text: text(for: vehicle, context: context))
    }

    private static func dollars(_ v: Double) -> String {
        v.formatted(.currency(code: "USD").precision(.fractionLength(0)))
    }
    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
}
