import XCTest
@testable import GarageHUDKit

/// The cross-surface honesty sweep — the structural guard this codebase was missing.
///
/// Three separate reviews found the same bug class (a crank figure labeled "whp", an estimate
/// labeled "measured") in three different places: W-004 fixed BuildProgress, W-021 fixed the
/// sheets, the Fable review found it again in BuildAssessment. Point fixes don't stop instance
/// #4; a quantified invariant does. This sweep renders EVERY pure textual surface for a matrix
/// of adversarial vehicles and asserts the honesty rules globally:
///
///   1. "whp" is earned by a real dyno — or explicitly framed as estimate/stock/goal/planned.
///   2. "measured" is earned by a real dyno — negations ("not yet measured") are fine.
///   3. The record is never denied: "no X parts are logged" / "no dyno logged" must not appear
///      when such a record exists (wishlist parts and numberless dynos are records too).
///   4. Planned money is always framed as planned, never presented as spend.
///   5. A car with nothing on record yields no numbers at all — nothing is ever fabricated.
///   6. Surfaces must not contradict each other on overdue-ness.
///
/// When a new textual surface is added, add it to `surfaces` — the sweep covers it for free.
/// (The fleet-sheet PDF is SwiftUI-rendered and not sweepable as text; its power readout and
/// legend logic are covered by FleetSheetTests + the shared helpers this sweep locks down.)
final class HonestySweepTests: XCTestCase {

    // MARK: - The surfaces

    private static let surfaces: [(name: String, render: (Vehicle) -> String)] = [
        ("buildSheet", { BuildSheetExporter.text(for: $0) }),
        ("grounding", { StewardGrounding.record(for: $0) }),
        ("observations", { Steward.observe($0).map { "\($0.statement) \($0.evidence)" }.joined(separator: " | ") }),
        ("assessment", { Steward.assess($0).map { "\($0.powerSummary) — \($0.headline)" } ?? "" }),
        ("nextStep", { Steward.nextStep($0).map { "\($0.action). \($0.rationale)" } ?? "" }),
        ("voice.power", { StewardConversation.reply(to: "what's my power", vehicle: $0).text }),
        ("voice.investment", { StewardConversation.reply(to: "what did I spend", vehicle: $0).text }),
        ("voice.watch", { StewardConversation.reply(to: "what should I watch", vehicle: $0).text }),
        ("voice.efficiency", { StewardConversation.reply(to: "cost per hp", vehicle: $0).text }),
        ("briefing", {
            let b = StewardBriefingBuilder.build(for: [$0])
            return "\(b.headline) \(b.spokenScript) \(b.serviceSummary ?? "")"
        }),
        ("tuneReadiness", {
            let t = Steward.tuneReadiness($0)
            return "\(t.headline) " + t.checks.map { "\($0.title): \($0.detail)" }.joined(separator: " | ")
        }),
        ("buildPlan", {
            let p = BuildPlanner.plan(for: $0)
            return (p.advisory ?? "") + " " + p.steps.map { "\($0.name): \($0.rationale)" }.joined(separator: " | ")
        }),
        // The buyer-facing PDF's words — the card renders exclusively from this model.
        ("fleetSheetCard", { FleetSheetCardModel.make(for: $0).sweepText }),
        // The whole-story export — full timeline, service record, provenance appendix.
        ("biography", { BiographyExporter.text(for: $0) }),
        // The "why should I trust this number" tap-throughs.
        ("provenance.power", { ProvenanceBuilder.power(for: $0)?.sweepText ?? "" }),
        ("provenance.investment", { ProvenanceBuilder.investment(for: $0)?.sweepText ?? "" }),
        ("provenance.odometer", { ProvenanceBuilder.odometer(for: $0)?.sweepText ?? "" }),
    ]

    // MARK: - The adversarial matrix

    private static func day(_ offset: Int) -> Date { Date(timeIntervalSinceNow: Double(offset) * 86_400) }

    private static func matrix() -> [(name: String, vehicle: Vehicle)] {
        var out: [(String, Vehicle)] = []

        var bare = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1)
        out.append(("bare", bare))

        var factoryOnly = bare
        factoryOnly.factoryHorsepower = 240
        factoryOnly.drivetrain = .rwd
        out.append(("factoryOnly", factoryOnly))

        var boosted = factoryOnly   // the H1 construction: supercharged, never dynoed
        boosted.parts = [
            Part(name: "Supercharger kit", category: .forcedInduction, status: .installed),
            Part(name: "Walbro 255 fuel pump", category: .fueling, status: .wishlist, cost: 140),
        ]
        out.append(("unDynoedBoosted", boosted))

        var numberless = factoryOnly
        numberless.factoryHorsepower = 155
        numberless.parts = [Part(name: "Exhaust", category: .exhaust, status: .installed)]
        numberless.performanceRecords = [PerformanceRecord(date: day(-10), type: .dyno)]
        out.append(("numberlessDyno", numberless))

        var negative = factoryOnly
        negative.factoryHorsepower = 140
        negative.performanceRecords = [PerformanceRecord(date: day(-1), type: .dyno, wheelHorsepower: -50)]
        out.append(("negativeDyno", negative))

        var measured = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        measured.drivetrain = .rwd
        measured.parts = [
            Part(name: "SC kit", category: .forcedInduction, status: .installed, cost: 5_760),
            Part(name: "Injectors", category: .fueling, status: .installed, cost: 945),
            Part(name: "Radiator", category: .cooling, status: .installed, cost: 600),
            Part(name: "Pistons", category: .engine, status: .installed, cost: 2_400),
            Part(name: "Clutch", category: .drivetrain, status: .installed, cost: 1_300),
        ]
        measured.performanceRecords = [PerformanceRecord(date: day(-30), type: .dyno, wheelHorsepower: 477)]
        out.append(("measured", measured))

        var planned = Vehicle(make: "Honda", model: "Civic", year: 2000, garageSlot: 1)
        planned.parts = [
            Part(name: "Intake", category: .engine, status: .installed, cost: 100),
            Part(name: "Garrett turbo kit", category: .forcedInduction, status: .wishlist, cost: 5_000),
        ]
        out.append(("plannedOnly", planned))

        var mileageOverdue = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        mileageOverdue.maintenance = [MaintenanceItem(name: "Oil change", intervalMonths: 12,
                                                      lastServiced: day(-30),
                                                      intervalMiles: 5_000, lastServicedMileage: 50_000)]
        mileageOverdue.buildEvents = [BuildEvent(date: day(0), title: "Odometer check", mileage: 58_000)]
        out.append(("mileageOverdue", mileageOverdue))

        var factoryTurbo = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1,
                                   factoryHorsepower: 224)
        factoryTurbo.engineDescription = "2.5L turbocharged flat-4"
        factoryTurbo.drivetrain = .awd
        factoryTurbo.parts = [Part(name: "Cobb Accessport", category: .electronics, status: .installed)]
        factoryTurbo.performanceRecords = [PerformanceRecord(date: day(-20), type: .dyno, wheelHorsepower: 381)]
        out.append(("factoryTurboTuned", factoryTurbo))

        var timeOverdue = bare
        timeOverdue.maintenance = [MaintenanceItem(name: "Coolant flush", intervalMonths: 6, lastServiced: day(-300))]
        out.append(("timeOverdue", timeOverdue))

        var outOfService = factoryOnly
        outOfService.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown", since: day(-40))
        out.append(("outOfService", outOfService))

        bare.buildGoal = BuildGoal(summary: "", targetWheelHP: 450)
        bare.factoryHorsepower = 240
        out.append(("goalNoDyno", bare))

        return out
    }

    /// Words that legitimately frame a wheel figure as something other than a measurement.
    private static let estimateMarkers = ["estimat", "stock", "goal", "target", "planned", "wishlist"]

    /// Phrases where "measured" appears in an honest negation.
    private static let measuredNegations = [
        "not yet measured", "no measured", "carries no measured figure", "never measured",
        "power not yet measured", "no wheel-power dyno", "not measured",
    ]

    // MARK: - The sweep

    func testEveryTextualSurfaceHoldsTheHonestyInvariants() {
        var violations: [String] = []

        for (vehicleName, vehicle) in Self.matrix() {
            for (surfaceName, render) in Self.surfaces {
                let text = render(vehicle)
                let context = "[\(vehicleName) × \(surfaceName)]"

                violations += unearnedWhpViolations(in: text, vehicle: vehicle, context: context)
                violations += unearnedMeasuredViolations(in: text, vehicle: vehicle, context: context)
                violations += recordDenialViolations(in: text, vehicle: vehicle, context: context)
                violations += plannedMoneyViolations(in: text, vehicle: vehicle, context: context)
                if vehicleName == "bare" {
                    violations += fabricationViolations(in: text, context: context)
                }
            }
        }

        violations += overdueConsistencyViolations()

        XCTAssertTrue(violations.isEmpty, "Honesty sweep violations:\n" + violations.joined(separator: "\n"))
    }

    // MARK: - Rules

    /// Rule 1: every "<number> whp" must be a measurement or sit next to an estimate marker.
    private func unearnedWhpViolations(in text: String, vehicle: Vehicle, context: String) -> [String] {
        guard !vehicle.hasMeasuredPower else { return [] }
        var out: [String] = []
        for range in matches(of: #"[\d,]+\s*whp"#, in: text) {
            let window = window(around: range, in: text).lowercased()
            if !Self.estimateMarkers.contains(where: window.contains) {
                out.append("\(context) unearned whp: …\(window)…")
            }
        }
        return out
    }

    /// Rule 2: "measured" only with a real dyno, except in negations.
    private func unearnedMeasuredViolations(in text: String, vehicle: Vehicle, context: String) -> [String] {
        guard !vehicle.hasMeasuredPower else { return [] }
        var scrubbed = text.lowercased()
        for negation in Self.measuredNegations {
            scrubbed = scrubbed.replacingOccurrences(of: negation, with: "")
        }
        guard scrubbed.contains("measured") else { return [] }
        return ["\(context) claims 'measured' without a real dyno figure: \(snippet(containing: "measured", in: text))"]
    }

    /// Rule 3: never deny a record that exists (wishlist parts and numberless dynos are records).
    private func recordDenialViolations(in text: String, vehicle: Vehicle, context: String) -> [String] {
        var out: [String] = []
        let lower = text.lowercased()
        let subsystemNames: [PartCategory: String] = [.fueling: "fuel system", .cooling: "cooling", .brakes: "brakes"]
        for (category, subsystem) in subsystemNames
        where vehicle.parts.contains(where: { $0.category == category && $0.status != .removed }) {
            if lower.contains("no \(subsystem) parts are logged") {
                out.append("\(context) denies a logged \(subsystem) part")
            }
        }
        if vehicle.performanceRecords.contains(where: { $0.type == .dyno }) {
            for phrase in ["no dyno logged", "no dyno is logged"] where lower.contains(phrase) {
                out.append("\(context) denies a logged dyno session ('\(phrase)')")
            }
        }
        return out
    }

    /// Rule 4: a wishlist part's cost may only appear framed as planned/wishlist.
    private func plannedMoneyViolations(in text: String, vehicle: Vehicle, context: String) -> [String] {
        var out: [String] = []
        for part in vehicle.parts where part.status == .wishlist {
            guard let cost = part.cost, cost >= 100 else { continue }   // tiny sums collide with other figures
            let needle = Int(cost).formatted(.number.grouping(.automatic))
            for range in matches(of: NSRegularExpression.escapedPattern(for: needle), in: text) {
                let window = window(around: range, in: text, radius: 140).lowercased()
                if !window.contains("planned") && !window.contains("wishlist") {
                    out.append("\(context) states planned \(needle) as fact: …\(window)…")
                }
            }
        }
        return out
    }

    /// Rule 5: a car with nothing on record yields no power figures and no dollars.
    private func fabricationViolations(in text: String, context: String) -> [String] {
        var out: [String] = []
        if !matches(of: #"\d+\s*w?hp\b"#, in: text).isEmpty {
            out.append("\(context) fabricated a power figure: \(text)")
        }
        if text.contains("$") {
            out.append("\(context) fabricated a dollar figure: \(text)")
        }
        return out
    }

    /// Rule 6: surfaces agree about overdue-ness — the header must never call a car overdue
    /// while the observation engine and voice say nothing stands out.
    private func overdueConsistencyViolations() -> [String] {
        var out: [String] = []
        for (name, v) in Self.matrix() {
            let summary = StewardBriefingBuilder.serviceSummary(for: [v])
            let saysOverdue = summary?.localizedCaseInsensitiveContains("overdue") == true
            guard saysOverdue else { continue }
            if !Steward.observe(v).contains(where: { $0.ruleID.hasPrefix("maintenance.overdue") }) {
                out.append("[\(name)] briefing header says overdue but Steward.observe has no overdue observation")
            }
            let watch = StewardConversation.reply(to: "what should I watch", vehicle: v).text
            if watch.contains("Nothing stands out") {
                out.append("[\(name)] briefing header says overdue but the voice Steward says nothing stands out")
            }
        }
        return out
    }

    // MARK: - Text helpers

    private func matches(of pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: ns).compactMap { Range($0.range, in: text) }
    }

    private func window(around range: Range<String.Index>, in text: String, radius: Int = 80) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[lower..<upper])
    }

    private func snippet(containing needle: String, in text: String) -> String {
        guard let range = text.range(of: needle, options: .caseInsensitive) else { return text }
        return window(around: range, in: text)
    }
}
