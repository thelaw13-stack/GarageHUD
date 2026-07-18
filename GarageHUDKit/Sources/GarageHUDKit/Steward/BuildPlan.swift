import Foundation

/// Where a build is headed. Deliberately small — a stated intent and an optional power target —
/// so the Steward can reason about the *path* to it without the owner filling in a form.
public struct BuildGoal: Codable, Hashable, Sendable {
    /// A one-line statement of intent, e.g. "Reliable 450 whp street car".
    public var summary: String
    /// An optional wheel-horsepower target, so progress can be measured, not just described.
    public var targetWheelHP: Double?

    public init(summary: String = "", targetWheelHP: Double? = nil) {
        self.summary = summary
        self.targetWheelHP = targetWheelHP
    }

    public var isSet: Bool { !summary.trimmingCharacters(in: .whitespaces).isEmpty || targetWheelHP != nil }
}

/// Phase 3 — the intent layer. GarageHUD knows what a car *is* and (via the Steward) what's off
/// about it now; BuildPlan reasons about where it's *going*: it orders the planned (wishlist) parts
/// into a sensible path — support and safety before power, respecting the sequence the Steward
/// already knows (fueling before boost) — and measures progress toward the goal. Same honesty rules:
/// it never invents a target, and it grades power progress by whether the current figure is measured.
public struct PlanStep: Identifiable, Equatable, Sendable {
    public enum Priority: Int, Sendable, Comparable {
        case other = 0, power = 1, sequence = 2, support = 3
        public static func < (l: Priority, r: Priority) -> Bool { l.rawValue < r.rawValue }
        public var label: String {
            switch self {
            case .support: return "SUPPORT"
            case .sequence: return "SEQUENCE"
            case .power: return "POWER"
            case .other: return "PLANNED"
            }
        }
    }
    public let id: UUID            // the wishlist part's id
    public let name: String
    public let category: PartCategory
    public let cost: Double?
    public let priority: Priority
    public let rationale: String
}

public struct BuildProgress: Equatable, Sendable {
    public let currentWHP: Double?     // wheel-normalized, so the fraction toward a wheel target is honest
    public let targetWHP: Double?
    public let powerMeasured: Bool     // is currentWHP from a dyno (vs. an estimated wheel baseline)?
    public let plannedRemaining: Double
    public let plannedCount: Int

    /// 0…1 toward the power target, when both a current figure and a target exist.
    public var powerFraction: Double? {
        guard let current = currentWHP, let target = targetWHP, target > 0 else { return nil }
        return min(1, max(0, current / target))
    }
}

public struct BuildPlan: Equatable, Sendable {
    public let goal: BuildGoal?
    public let steps: [PlanStep]
    public let progress: BuildProgress
    /// A single line of guidance about the plan's shape (e.g. a sequence warning), or nil.
    public let advisory: String?

    public var isEmpty: Bool { steps.isEmpty && (goal?.isSet != true) }
}

public enum BuildPlanner {
    public static func plan(for vehicle: Vehicle, context: StewardContext = .live) -> BuildPlan {
        let planned = vehicle.plannedParts
        let boosted = vehicle.runsElevatedBoost   // incl. a tuned-up factory-boosted platform (W-045)
        // Support categories that matter more once the car is past the owner's
        // driveline-attention level (W-044).
        let powerUp = vehicle.powerDemandsDrivelineAttention
        let plansForcedInduction = planned.contains { $0.category == .forcedInduction }

        let steps = planned.map { part -> PlanStep in
            let (priority, rationale) = classify(part, vehicle: vehicle, boosted: boosted,
                                                 powerUp: powerUp, plansForcedInduction: plansForcedInduction)
            return PlanStep(id: part.id, name: part.name, category: part.category,
                            cost: part.cost, priority: priority, rationale: rationale)
        }
        .sorted { a, b in
            if a.priority != b.priority { return a.priority > b.priority }
            return (a.cost ?? 0) < (b.cost ?? 0)   // cheaper support wins ties — knock out easy ones
        }

        let progress = BuildProgress(
            currentWHP: vehicle.currentWheelHorsepowerEstimate,   // wheel-to-wheel vs. a wheel target
            targetWHP: vehicle.buildGoal?.targetWheelHP,
            powerMeasured: vehicle.hasMeasuredPower,
            plannedRemaining: vehicle.plannedSpend,
            plannedCount: planned.count)

        return BuildPlan(goal: vehicle.buildGoal, steps: steps, progress: progress,
                         advisory: advisory(for: vehicle, planned: planned, plansForcedInduction: plansForcedInduction))
    }

    /// Priority + why, per planned part.
    private static func classify(_ part: Part, vehicle: Vehicle, boosted: Bool, powerUp: Bool,
                                 plansForcedInduction: Bool) -> (PlanStep.Priority, String) {
        switch part.category {
        case .fueling:
            // Fueling must lead any boost — it's the classic sequence hazard the Steward flags.
            if plansForcedInduction || boosted {
                return (.sequence, "Do this before adding boost — fueling has to lead the air.")
            }
            return (.support, "Feeds the extra air your build will move.")
        case .cooling:
            return (boosted || plansForcedInduction ? .support : .other,
                    "Manages the added heat of a boosted setup.")
        case .brakes:
            return (powerUp || boosted ? .support : .other,
                    "Braking should keep pace with the power and grip you're adding.")
        case .suspension, .wheelsAndTires:
            return (.other, "Puts the power down and sharpens the car.")
        case .forcedInduction, .engine:
            return (.power, "The core power adder toward your goal.")
        case .exhaust, .drivetrain, .electronics:
            return (.power, "Supports and frees up the power you're building.")
        case .exterior, .interior, .uncategorized:
            return (.other, "On the list.")
        }
    }

    private static func advisory(for vehicle: Vehicle, planned: [Part], plansForcedInduction: Bool) -> String? {
        // Planning boost with no fueling recorded or planned is the sequence trap worth calling out.
        let hasFuelingCovered = vehicle.knowledge(of: .fueling) == .confirmedPresent
            || planned.contains { $0.category == .fueling }
        if plansForcedInduction && !hasFuelingCovered {
            return "Your plan adds boost but no fueling is recorded or planned — sort fueling first."
        }
        if let target = vehicle.buildGoal?.targetWheelHP, let current = vehicle.currentWheelHorsepowerEstimate,
           current >= target {
            return "You're at your \(Int(target)) whp goal — the plan below is refinement from here."
        }
        return nil
    }
}
