import Foundation

/// Where a value came from — its origin, distinct from how precise it is (ADR-0006).
///
/// GarageHUD already carries an evidence *band* (Confirmed/Strong/…/Insufficient) for how sure a
/// number is. Provenance is the other axis: a window-sticker figure and a number the owner typed to
/// fill a blank can both be "roughly right", but only one has a source. Without this, a guess is
/// indistinguishable from a measurement, and a derivation built on the guess inherits a confidence it
/// never earned — the Baja's placeholder 75 hp becoming a hard-looking 63 whp baseline (W-070).
///
/// Ordered weakest to strongest, so the monotonic rule (ADR-0006 §4) is a plain `min`.
public enum Provenance: Int, Codable, Hashable, Sendable, Comparable, CaseIterable {
    /// Not recorded. The honest blank — never a fabricated stand-in.
    case unknown = 0
    /// A value carried over from before provenance existed. Strength of an estimate for the
    /// monotonic rule (so it can't launder a derivation), but **silent** in the UI — rendered
    /// exactly as today, never labelled a guess. This is the migration's promise: no owner's years
    /// of data are retroactively cast into doubt.
    case unspecified = 1
    /// The owner's approximation. Honest, but claims no source. The default for a typed number.
    case estimated = 2
    /// Transcribed from a real reference: window sticker, build sheet, factory spec.
    case sourced = 3
    /// From an instrument — a dyno pull. The only origin that may ever read as "measured".
    case measured = 4

    public static func < (a: Provenance, b: Provenance) -> Bool { a.rawValue < b.rawValue }

    /// The weakest of several origins — what a derived figure inherits. Confidence can only ever
    /// decrease along a derivation, never increase. Empty inputs → `unknown`: a figure derived from
    /// nothing is not knowledge.
    public static func weakest(_ provenances: [Provenance]) -> Provenance {
        provenances.min() ?? .unknown
    }

    /// May a value of this origin ever be presented as a hard, measured fact? Only a real
    /// instrument reading. Everything else must read as an estimate or be suppressed.
    public var canPresentAsMeasured: Bool { self == .measured }

    /// May this origin seed a derived figure that is shown with confidence? `unknown` may not — a
    /// derivation from an unrecorded value is a fabrication, and the app must say "not recorded"
    /// rather than invent a baseline (the root-cause half of W-070).
    public var canSeedDerivation: Bool { self != .unknown }

    /// Short, owner-facing origin tag, or nil when nothing should be shown. `unspecified` is
    /// deliberately nil — a legacy value carries no origin claim, so it renders as it always has.
    public var label: String? {
        switch self {
        case .unknown:     return "not recorded"
        case .unspecified: return nil
        case .estimated:   return "estimate"
        case .sourced:     return "documented"
        case .measured:    return "measured"
        }
    }
}
