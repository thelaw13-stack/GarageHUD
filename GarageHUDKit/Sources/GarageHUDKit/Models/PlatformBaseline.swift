import Foundation

/// Sourced per-platform baselines — the anti-guess. The Steward's live limits used to be flat
/// numbers typed once (an 18 psi boost caution applied to a supercharged S2000 and a turbo Subaru
/// alike, and a coolant limit asserted on an air-cooled engine that has no coolant). Each figure
/// here is grounded in the platform's real tuning behavior and carries its `source`, so a live
/// caution only fires where the number actually means something *for that car*.
///
/// The catalog is deliberately extensible: to add a platform, add an entry **with a source**. A new
/// baseline that can't cite where its numbers came from doesn't belong here — that's the rule that
/// keeps this from drifting back into guesses.
public struct PlatformBaseline: Sendable, Equatable {
    public let id: String
    public let displayName: String
    /// Lowercased substrings matched against "year make model trim engineDescription". First hit wins.
    public let matches: [String]
    /// Air-cooled engines have no coolant temperature — a coolant limit on one is false authority.
    public let airCooled: Bool
    /// The boost level at which a boosted example of this platform is "watch it" on a stock-ish
    /// setup — used as the live caution only when the car actually `runsBoost`. nil → fall back to
    /// the conservative generic. This is a caution (amber), not a hard ceiling; the owner's
    /// `maxSustainedBoostPsi` always wins.
    public let boostCautionPsi: Double?
    /// Where the numbers came from.
    public let source: String

    /// Conservative caution for a boosted platform we haven't characterized — below the common
    /// street-turbo ceiling, so it errs toward warning early. Tagged generic on purpose.
    public static let genericBoostedCautionPsi: Double = 16

    /// The platform baseline matching a vehicle, if one is known.
    public static func baseline(for vehicle: Vehicle) -> PlatformBaseline? {
        let hay = "\(vehicle.year) \(vehicle.make) \(vehicle.model) \(vehicle.trim) \(vehicle.engineDescription)"
            .lowercased()
        return catalog.first { entry in entry.matches.contains { hay.contains($0) } }
    }

    public static let catalog: [PlatformBaseline] = [
        // Tim's garage — the four cars this was researched against.
        PlatformBaseline(
            id: "honda-s2000", displayName: "Honda S2000 (F20C/F22C)",
            matches: ["s2000", "ap1", "ap2", "f20c", "f22c"],
            airCooled: false, boostCautionPsi: 13,
            source: "Kraftwerks Rotrex SC kits run ~8-12 psi, high-boost pulley ~12+ (S2KI, Kraftwerks); F22 street builds live at the top of that band. Caution set just above the common level."),
        PlatformBaseline(
            id: "subaru-ej-turbo", displayName: "Subaru EJ turbo (WRX/STI/Forester XT/Legacy GT)",
            matches: ["wrx", "sti", "forester xt", "legacy gt", "ej255", "ej257"],
            airCooled: false, boostCautionPsi: 17,
            source: "Stock TD04 peaks ~12 psi and is safe to ~16-18 on pump gas, 17 the safer edge (subaruforester.org, NASIOC). Above that wants meth/water or race fuel."),
        PlatformBaseline(
            id: "toyota-tundra-57", displayName: "Toyota Tundra 5.7 (3UR-FE)",
            matches: ["tundra", "3ur-fe", "3urfe"],
            airCooled: false, boostCautionPsi: 8,
            source: "5.7L 3UR-FE is naturally aspirated (381 hp); the only forced-induction path is a Magnuson TVS kit at low boost ~7-9 psi. NA cars get no boost caution at all — this applies only if one is ever added."),
        PlatformBaseline(
            id: "vw-aircooled-type1", displayName: "VW air-cooled Type 1 (Baja/Beetle)",
            matches: ["baja", "beetle", "type 1", "type1", "air-cooled", "aircooled"],
            airCooled: true, boostCautionPsi: nil,
            source: "Type 1 flat-four is air-cooled — no coolant system at all; heat is managed by oil temp and cylinder-head temp (VW air-cooled engine, Wikipedia). Naturally aspirated. A coolant limit here is meaningless."),
    ]
}

public extension Vehicle {
    /// The sourced baseline for this car's platform, if known.
    var platformBaseline: PlatformBaseline? { PlatformBaseline.baseline(for: self) }

    /// True only for a platform explicitly known to be air-cooled — the safe direction: an unknown
    /// platform is assumed liquid-cooled so a real coolant caution is never silently suppressed.
    var isAirCooled: Bool { platformBaseline?.airCooled ?? false }

    /// The live boost caution to apply: nil when boost isn't a meaningful signal (naturally
    /// aspirated), else the platform's sourced value, else a conservative generic. The owner's
    /// envelope override supersedes this entirely.
    var defaultBoostCautionPsi: Double? {
        guard runsBoost else { return nil }
        return platformBaseline?.boostCautionPsi ?? PlatformBaseline.genericBoostedCautionPsi
    }
}
