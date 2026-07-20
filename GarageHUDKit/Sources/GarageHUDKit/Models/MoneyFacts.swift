import Foundation

/// The three money facts a build carries, kept deliberately distinct (Constitution rule 4;
/// ADR-0006 §5). They answer different questions and must never collapse into one number:
///
///   • **acquisition** — what the owner paid to *buy* the vehicle
///   • **build** — what the owner has *invested building* it (parts, labour, tuning)
///   • **service** — what the owner has spent *maintaining* it
///
/// The app already honours the distinction everywhere downstream — the Baja's $8,000 acquisition
/// cost, entered into the build slot, was faithfully reported *as build spend* by every surface.
/// The gap W-072 found is at entry: nothing names the three roles as a set where a value is typed,
/// so an acquisition cost can land in the build field. This type is the single source of truth for
/// their names and their distinctness, so the wording can't drift between surfaces.
public enum MoneyFact: CaseIterable, Sendable {
    case acquisition
    case build
    case service

    /// Short field label — what this figure *is*.
    public var role: String {
        switch self {
        case .acquisition: return "Acquisition"
        case .build:       return "Build investment"
        case .service:     return "Service spend"
        }
    }

    /// One line naming the fact and, crucially, what it is *not* — the guard at the point of entry.
    public var distinctNote: String {
        switch self {
        case .acquisition: return "What you paid to buy the vehicle — not build spend."
        case .build:       return "Invested building it: parts, labour, tuning — not the purchase price."
        case .service:     return "Spent maintaining it — separate from both."
        }
    }
}

public extension Vehicle {
    /// The value of each money fact right now, in dollars, or nil when not recorded. The three are
    /// read from *separate* stored facts and are never summed — a caller that wants a headline picks
    /// one, it never adds them.
    func amount(of fact: MoneyFact) -> Double? {
        switch fact {
        case .acquisition: return purchasePrice
        case .build:       return totalInvested > 0 ? totalInvested : nil
        case .service:     return serviceSpend > 0 ? serviceSpend : nil
        }
    }
}
