import Foundation

/// The investment headline with every honest label pre-paired — the money twin of `PowerFigure`.
///
/// The "total invested" number carries a three-way story: it's either the live sum of priced
/// parts, or a larger documented lump sum standing in while parts are only partly priced — and
/// each state has its own reconcile figure and wording. Five surfaces (build sheet, grounding,
/// fleet sheet, Specs, voice) were each re-deriving which word goes with which state by hand;
/// this type defines every pairing once, so a surface cannot say "documented" about a
/// parts-driven total (or vice versa) without visibly going around it.
public struct InvestmentFigure: Equatable, Sendable {
    /// The headline number — `Vehicle.totalInvested`, always > 0 (nil figure otherwise).
    public let total: Double
    /// True when the total is the live priced-parts sum (editing a part price moves it).
    public let isLiveFromParts: Bool
    /// When the parts-sum leads and a meaningfully different documented figure exists — the
    /// documented figure, for reconciliation copy. Nil otherwise.
    public let documentedReconcile: Double?
    /// When a larger documented total leads — how much of it is priced in parts so far.
    public let pricedSoFar: Double?

    // MARK: Pre-paired wording — every surface reads one of these, never re-derives the pairing.

    /// Compact caption, e.g. fleet-sheet mini-stat: "logged parts" / "documented".
    public var sourceShort: String { isLiveFromParts ? "logged parts" : "documented" }

    /// Bracketed grounding form: "sum of logged parts" / "documented lump sum".
    public var sourceLong: String { isLiveFromParts ? "sum of logged parts" : "documented lump sum" }

    /// Build-sheet phrase following the amount: "in logged parts" / "documented".
    public var sheetPhrase: String { isLiveFromParts ? "in logged parts" : "documented" }

    /// Voice verb: "you've logged/documented $X invested".
    public var spokenVerb: String { isLiveFromParts ? "logged" : "documented" }

    /// The Specs explanation sentence for the current state.
    public var explanation: String {
        if isLiveFromParts {
            return "Summed live from your installed parts — edit a part's price and this updates."
        }
        if pricedSoFar != nil {
            return "Your build-sheet total is higher than the parts you've priced — it likely covers labor or parts not yet priced — so this shows the build-sheet figure."
        }
        return "No parts priced yet, so this shows your build-sheet total."
    }
}

public extension Vehicle {
    /// The investment headline with its labels pre-paired, or nil when nothing is invested —
    /// a surface with no figure shows no money.
    var investmentFigure: InvestmentFigure? {
        guard totalInvested > 0 else { return nil }
        return InvestmentFigure(total: totalInvested,
                                isLiveFromParts: investmentIsLiveFromParts,
                                documentedReconcile: documentedReconcileFigure,
                                pricedSoFar: pricedPartsSoFar)
    }
}
