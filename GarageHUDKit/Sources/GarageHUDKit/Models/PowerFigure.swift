import Foundation

/// A power figure with its honest label pre-paired to its evidence — the only way a surface
/// should obtain a number it intends to print.
///
/// Three reviews found the same bug in four places: a call site read `currentHorsepowerEstimate`
/// (which can be a factory *crank* rating) and hardcoded "whp" next to it. The value and its
/// label lived apart, and every surface had to re-pair them correctly by hand. `PowerFigure`
/// closes that gap: the unit and qualifier are properties of the figure itself, derived from
/// whether the number is a real wheel measurement, so a surface *cannot* print the value with
/// the wrong word without visibly going around this type.
public struct PowerFigure: Equatable, Sendable {
    /// The number to show.
    public let value: Double
    /// True only when `value` is a real wheel-dyno measurement (`Vehicle.hasMeasuredPower`).
    public let isMeasured: Bool

    public init(value: Double, isMeasured: Bool) {
        self.value = value
        self.isMeasured = isMeasured
    }

    /// "whp" for a measurement, "hp" for a factory rating — the unit *is* the honesty.
    public var unit: String { isMeasured ? "whp" : "hp" }

    /// The provenance word a fuller display pairs with the number.
    public var qualifier: String { isMeasured ? "measured" : "factory rated" }

    /// Compact display, e.g. "477 whp" / "240 hp" — for tight UI where the unit alone
    /// must carry the honesty.
    public var compactLabel: String { "\(Int(value)) \(unit)" }

    /// Full display, e.g. "477 whp (measured)" / "240 hp (factory rated)" — for documents.
    public var labeled: String { "\(compactLabel) (\(qualifier))" }
}

public extension Vehicle {
    /// The best current power figure to show, with its label already paired: the latest real
    /// wheel measurement if there is one, else the factory rating marked as such. Nil when
    /// nothing is on record — a surface with no figure shows no number.
    var currentPowerFigure: PowerFigure? {
        currentHorsepowerEstimate.map { PowerFigure(value: $0, isMeasured: hasMeasuredPower) }
    }
}
