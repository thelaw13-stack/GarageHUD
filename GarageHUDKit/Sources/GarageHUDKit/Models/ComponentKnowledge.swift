import Foundation

/// What we actually *know* about a subsystem — the distinction the review demands between
/// "not logged" and "not installed". Absence of a logged part is not evidence of a missing
/// physical system; it's just an undocumented one.
public enum ComponentKnowledge: Sendable, Equatable {
    case confirmedPresent   // an installed part in this category is on record
    case confirmedAbsent    // the owner confirmed the factory system remains (no upgrade)
    case undocumented       // nothing logged either way, but the record has other content
    case unknown            // the record is effectively empty — we know nothing at all
}

/// The measurement basis behind a horsepower figure. Comparing a measured wheel number
/// against a factory *crank* rating is an approximation, and the reasoning must say so
/// rather than presenting a dollars-per-hp figure as if it were dyno-corrected truth.
public enum PowerBasis: String, Sendable, Codable, Equatable, Hashable, CaseIterable, Identifiable {
    case factoryCrank       // manufacturer rating, at the crank
    case estimatedCrank     // an estimate referred to the crank
    case measuredWheel      // measured on a chassis dyno, at the wheels
    case unknown

    public var id: String { rawValue }

    public var describes: String {
        switch self {
        case .factoryCrank: return "factory crank"
        case .estimatedCrank: return "estimated crank"
        case .measuredWheel: return "measured wheel"
        case .unknown: return "unspecified"
        }
    }

    public var displayName: String {
        switch self {
        case .factoryCrank: return "Factory (crank)"
        case .estimatedCrank: return "Estimated (crank)"
        case .measuredWheel: return "Measured (wheel)"
        case .unknown: return "Unspecified"
        }
    }
}

/// Drivetrain layout, used to estimate drivetrain loss so a factory *crank* rating can be
/// brought to a *wheel*-equivalent baseline — the normalization that lets cost-per-hp compare
/// wheel-to-wheel instead of wheel-to-crank. The fractions are typical rule-of-thumb losses,
/// not measured for a specific car, so any result stays explicitly an estimate.
public enum Drivetrain: String, Sendable, Codable, Equatable, Hashable, CaseIterable, Identifiable {
    case fwd, rwd, awd, fourWD, twoWD, unknown

    public var id: String { rawValue }

    /// Typical driveline loss as a fraction of crank power. `unknown` uses a conservative
    /// middle assumption so an estimate is still possible, flagged as assumed. 4x4 carries a
    /// transfer case (more loss than a 2x4).
    public var typicalLossFraction: Double {
        switch self {
        case .fwd: return 0.10
        case .rwd: return 0.15
        case .twoWD: return 0.15
        case .awd: return 0.20
        case .fourWD: return 0.20
        case .unknown: return 0.15
        }
    }

    public var label: String {
        switch self {
        case .fwd: return "FWD"; case .rwd: return "RWD"; case .awd: return "AWD"
        case .fourWD: return "4X4"; case .twoWD: return "2X4"; case .unknown: return "drivetrain"
        }
    }

    public var displayName: String {
        switch self {
        case .fwd: return "FWD"; case .rwd: return "RWD"; case .awd: return "AWD"
        case .fourWD: return "4x4 (4WD)"; case .twoWD: return "2x4 (2WD)"; case .unknown: return "Unspecified"
        }
    }

    /// Best-effort drivetrain from a vehicle's identifiers. Scans the trim/model for explicit
    /// drive markers first (4x4, AWD, quattro, 2WD…), then falls back to well-known models. Returns
    /// `.unknown` when it's genuinely ambiguous (e.g. a truck with no 4x4/2wd trim) rather than
    /// guessing — the honest default the owner can override.
    public static func inferred(make: String, model: String, trim: String = "") -> Drivetrain {
        let text = "\(make) \(model) \(trim)".lowercased()
        func has(_ needles: [String]) -> Bool { needles.contains { text.contains($0) } }

        // Explicit drive markers win.
        if has(["4x4", "4wd", "four wheel", "four-wheel"]) { return .fourWD }
        if has(["2x4", "2wd", "two wheel", "two-wheel"]) { return .twoWD }
        if has(["awd", "quattro", "4matic", "xdrive", "4motion", "all wheel", "all-wheel", "sh-awd"]) { return .awd }
        if has([" fwd", "fwd ", "front wheel", "front-wheel"]) { return .fwd }
        if has([" rwd", "rwd ", "rear wheel", "rear-wheel"]) { return .rwd }

        // Well-known models where the layout is unambiguous.
        if has(["s2000", "miata", "mx-5", "mx5", "supra", "brz", "gr86", "frs", "fr-s", "corvette",
                "mustang", "camaro", "challenger", "370z", "350z", "rx-7", "rx7", "rx-8", "rx8",
                "beetle", "baja"]) { return .rwd }
        if has(["subaru", "wrx", "sti", "forester", "outback", "crosstrek", "impreza", "audi"]) { return .awd }
        if has(["civic", "integra", "prius", "golf gti", "gti", "focus", "fiesta"]) { return .fwd }

        // Trucks/SUVs: 4x4 vs 2x4 is a trim/option, not derivable from the model — stay honest.
        return .unknown
    }
}

public extension Vehicle {
    /// What we know about a given subsystem, honestly. An empty record yields `.unknown`
    /// (so a freshly created or barely-imported vehicle is never warned at), a logged install
    /// yields `.confirmedPresent`, an explicit stock confirmation yields `.confirmedAbsent`,
    /// and everything else is `.undocumented` — a gap in the *record*, not proof of a gap in
    /// the *car*.
    func knowledge(of category: PartCategory) -> ComponentKnowledge {
        if parts.isEmpty && confirmedStockSystems.isEmpty { return .unknown }
        if parts.contains(where: { $0.category == category && $0.status == .installed }) {
            return .confirmedPresent
        }
        if confirmedStockSystems.contains(category) { return .confirmedAbsent }
        return .undocumented
    }

    /// A rough completeness signal used to grade `.undocumented` gaps: a richly documented
    /// build with a missing category is more suspicious than a sparse imported record.
    var isWellDocumented: Bool { installedPartsCount >= 6 }

    /// The owner's calibration (Tim, 2026-07-18, W-044): "I won't touch the transmission till
    /// over 450 HP, wouldn't touch the clutch till then." Driveline and brake attention keys on
    /// crossing this absolute wheel-power level — NOT on a flat gain-over-stock, which flagged
    /// a stage-1 factory-turbo Subaru (a ~25% bump the factory driveline was engineered for)
    /// the same as a built car making double stock.
    static let drivelineAttentionWheelHP: Double = 450

    /// True when the car's wheel-honest output exceeds the owner's driveline-attention level —
    /// the gate for clutch/drivetrain and power-triggered brake scrutiny.
    var powerDemandsDrivelineAttention: Bool {
        (currentWheelHorsepowerEstimate ?? 0) > Self.drivelineAttentionWheelHP
    }

    /// The live operating limits for this car — the owner's override, or a default derived
    /// from what we know about it.
    var operatingEnvelope: OperatingEnvelope { operatingEnvelopeOverride ?? .default(for: self) }
}
