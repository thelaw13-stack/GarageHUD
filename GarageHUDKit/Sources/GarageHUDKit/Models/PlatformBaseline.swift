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
    /// The make(s) this entry may EVER match — the anchor. Bare-substring matching without it
    /// classified a 2005 Subaru Baja Turbo (water-cooled, OBD-II) as an air-cooled VW Type 1,
    /// silently stripping its coolant warnings and refusing it telemetry (Fable review #2). A
    /// classifier is a judgment constant too; it doesn't get to guess.
    public let makeTokens: [String]
    /// Lowercased substrings matched against "year make model trim engineDescription".
    public let matches: [String]
    /// Last model year this entry can describe (nil = current). Guards generational splits:
    /// "Beetle" means air-cooled Type 1 only up to 2003 — a 2019 Beetle is a water-cooled TSI.
    public let yearMax: Int?
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

    /// The platform baseline matching a vehicle, if one is known. An entry must match the MAKE,
    /// a model/engine substring, and the year window — never a bare substring alone.
    public static func baseline(for vehicle: Vehicle) -> PlatformBaseline? {
        let make = vehicle.make.lowercased()
        let hay = "\(vehicle.year) \(vehicle.make) \(vehicle.model) \(vehicle.trim) \(vehicle.engineDescription)"
            .lowercased()
        return catalog.first { entry in
            entry.makeTokens.contains(where: { make.contains($0) })
                && (entry.yearMax.map { vehicle.year <= $0 } ?? true)
                && entry.matches.contains { hay.contains($0) }
        }
    }

    public static let catalog: [PlatformBaseline] = [
        // Tim's garage — the four cars this was researched against.
        PlatformBaseline(
            id: "honda-s2000", displayName: "Honda S2000 (F20C/F22C)",
            makeTokens: ["honda"],
            matches: ["s2000", "ap1", "ap2", "f20c", "f22c"], yearMax: nil,
            airCooled: false, boostCautionPsi: 13,
            source: "Kraftwerks Rotrex SC kits run ~8-12 psi, high-boost pulley ~12+ (S2KI, Kraftwerks); F22 street builds live at the top of that band. Caution set just above the common level."),
        PlatformBaseline(
            id: "subaru-ej-turbo", displayName: "Subaru EJ turbo (WRX/STI/Forester XT/Legacy GT)",
            makeTokens: ["subaru"],
            matches: ["wrx", "sti", "forester xt", "legacy gt", "ej255", "ej257"], yearMax: nil,
            airCooled: false, boostCautionPsi: 17,
            source: "Stock TD04 peaks ~12 psi and is safe to ~16-18 on pump gas, 17 the safer edge (subaruforester.org, NASIOC). Above that wants meth/water or race fuel."),
        PlatformBaseline(
            id: "toyota-tundra-57", displayName: "Toyota Tundra 5.7 (3UR-FE)",
            makeTokens: ["toyota"],
            matches: ["tundra", "3ur-fe", "3urfe"], yearMax: nil,
            airCooled: false, boostCautionPsi: 8,
            source: "5.7L 3UR-FE is naturally aspirated (381 hp); the only forced-induction path is a Magnuson TVS kit at low boost ~7-9 psi. NA cars get no boost caution at all — this applies only if one is ever added."),
        PlatformBaseline(
            id: "vw-aircooled-type1", displayName: "VW air-cooled Type 1 (Baja/Beetle)",
            makeTokens: ["volkswagen", "vw"],
            matches: ["baja", "beetle", "type 1", "type1", "air-cooled", "aircooled"], yearMax: 2003,
            airCooled: true, boostCautionPsi: nil,
            source: "Type 1 flat-four is air-cooled — no coolant system at all; heat is managed by oil temp and cylinder-head temp (VW air-cooled engine, Wikipedia). Naturally aspirated. Mexican production ended 2003; later Beetles are water-cooled and must not match. A coolant limit here is meaningless."),
    ]
}

public extension Vehicle {
    /// The sourced baseline for this car's platform, if known.
    var platformBaseline: PlatformBaseline? { PlatformBaseline.baseline(for: self) }

    /// True for a platform explicitly known to be air-cooled, or when the owner's own engine
    /// description says so ("air-cooled") — the owner's words about their car outrank the
    /// catalog. Safe direction otherwise: an unknown platform is assumed liquid-cooled so a
    /// real coolant caution is never silently suppressed.
    var isAirCooled: Bool {
        if let known = platformBaseline?.airCooled, known { return true }
        let engine = engineDescription.lowercased()
        return engine.contains("air-cooled") || engine.contains("aircooled") || engine.contains("air cooled")
    }

    /// Whether this car has an OBD-II port to connect a live adapter to. The owner's override
    /// wins outright — swapped classics run modern ECUs with OBD-II gateways, and gray-market
    /// imports break any year rule. The heuristic (US mandate year, and never on an air-cooled
    /// classic) only applies when the owner hasn't said. Registered as a classifier in
    /// docs/STEWARD_THRESHOLDS.md.
    var supportsOBD2: Bool { obd2Override ?? (!isAirCooled && year >= 1996) }

    /// The live boost caution to apply: nil when boost isn't a meaningful signal (naturally
    /// aspirated), else the platform's sourced value, else a conservative generic. The owner's
    /// envelope override supersedes this entirely.
    var defaultBoostCautionPsi: Double? {
        guard runsBoost else { return nil }
        return platformBaseline?.boostCautionPsi ?? PlatformBaseline.genericBoostedCautionPsi
    }
}
