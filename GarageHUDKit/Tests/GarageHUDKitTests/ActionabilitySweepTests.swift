import XCTest
@testable import GarageHUDKit

/// The actionability sweep — Tim's question, mechanized: "what do you want the user to do
/// right here?" An instruction must carry a door. The honesty sweep guarantees the app never
/// SAYS anything unearned; this guarantees it never ASKS anything unanswerable:
///
///   1. Every non-informational observation (caution/advisory) must resolve to at least one
///      concrete in-app action.
///   2. Every next step must carry resolvable verbs — except the one documented exemption:
///      the out-of-service rebuild step, whose only in-place resolution would contradict its
///      own words (W-039) and whose real surface is the rebuild checklist.
///
/// Found the hard way (W-041): "Address clutch/drivetrain" shipped with no path to any of its
/// three intended responses, because gap rules only covered three categories. This sweep makes
/// instance #2 of that class impossible to ship quietly.
final class ActionabilitySweepTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Date(timeIntervalSinceNow: Double(offset) * 86_400) }

    /// Vehicles chosen to trigger every observation family and every next-step branch.
    private func matrix() -> [(name: String, vehicle: Vehicle)] {
        var out: [(String, Vehicle)] = []

        var boosted = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 1, factoryHorsepower: 240)
        boosted.drivetrain = .rwd
        boosted.parts = [
            Part(name: "SC kit", category: .forcedInduction, status: .installed, installDate: day(-400)),
            Part(name: "Injectors", category: .fueling, status: .installed, installDate: day(-100)),
        ]
        boosted.performanceRecords = [PerformanceRecord(date: day(-200), type: .dyno, wheelHorsepower: 340)]
        out.append(("boostedSequenceStale", boosted))   // gap, sequence, stale-tune territory

        var fozzy = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 2, factoryHorsepower: 224)
        fozzy.drivetrain = .awd
        fozzy.parts = [Part(name: "Big turbo", category: .forcedInduction, status: .installed),
                       Part(name: "Injectors", category: .fueling, status: .installed),
                       Part(name: "FMIC", category: .cooling, status: .installed),
                       Part(name: "Forged pistons", category: .engine, status: .installed)]
        // Past the owner's 450-whp driveline-attention line (W-044) — clutch is in scope.
        fozzy.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 480)]
        out.append(("fozzyDrivetrainOpen", fozzy))      // the W-041 case: non-gap-rule category

        var overdue = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 3)
        overdue.maintenance = [MaintenanceItem(name: "Oil change", intervalMonths: 12, lastServiced: day(-30),
                                               intervalMiles: 5_000, lastServicedMileage: 50_000)]
        overdue.buildEvents = [BuildEvent(date: day(0), title: "Odometer", mileage: 58_000)]
        out.append(("mileageOverdue", overdue))

        var regressed = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 4)
        regressed.buildEvents = [BuildEvent(date: day(-30), title: "Odometer", mileage: 58_000),
                                 BuildEvent(date: day(0), title: "Odometer", mileage: 51_000)]
        out.append(("odometerRegression", regressed))

        var torn = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 5)
        torn.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown")
        out.append(("teardown", torn))

        // Tim's second Fozzy report: drivetrain already confirmed stock, yet the surface kept
        // offering "confirm it's stock" — a circular verb whose tap is a no-op.
        var stockConfirmed = fozzy
        stockConfirmed.garageSlot = 6
        stockConfirmed.confirmedStockSystems = [.drivetrain, .brakes]
        out.append(("confirmedStockUnderLoad", stockConfirmed))

        return out
    }

    func testEveryInstructionCarriesADoor() {
        var violations: [String] = []

        for (name, vehicle) in matrix() {
            // 1. Non-informational observations must be actionable — and no verb may be
            //    circular (asking the user to set a state that's already set: a no-op tap
            //    that never resolves).
            for obs in Steward.observe(vehicle) where obs.tone != .informational {
                let options = StewardResolution.options(for: obs, in: vehicle)
                if options.isEmpty {
                    violations.append("[\(name)] \(obs.ruleID) asks (\"\(obs.statement)\") but offers no action")
                }
                violations += circularVerbViolations(options, in: vehicle, context: "[\(name)] \(obs.ruleID)")
            }

            // 2. Next steps carry resolvable verbs, or are the documented teardown exemption.
            if let step = Steward.nextStep(vehicle) {
                if let source = step.source {
                    let options = StewardResolution.options(for: source, in: vehicle)
                    if options.isEmpty {
                        violations.append("[\(name)] next step \"\(step.action)\" carries a source with no verbs")
                    }
                    violations += circularVerbViolations(options, in: vehicle, context: "[\(name)] next step")
                } else if !vehicle.serviceStatus.isInService {
                    violations.append("[\(name)] next step \"\(step.action)\" is an instruction without a door")
                }
            }
        }

        XCTAssertTrue(violations.isEmpty, "Actionability violations:\n" + violations.joined(separator: "\n"))
    }

    /// A verb is circular when its effect is already true — tapping it changes nothing.
    private func circularVerbViolations(_ options: [ResolutionOption], in vehicle: Vehicle,
                                        context: String) -> [String] {
        options.compactMap { option in
            if case .confirmStock(let cat) = option.action,
               vehicle.knowledge(of: cat) == .confirmedAbsent {
                return "\(context) offers circular verb \"\(option.title)\" — \(cat.rawValue) is already confirmed stock"
            }
            return nil
        }
    }
}
