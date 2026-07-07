import Foundation

/// The Steward namespace forms the basis of higher‑level reasoning in GarageHUD.
///
/// In Sprint 2 we introduce a lightweight shell around existing capabilities such as
/// build suggestions and cost metrics. The intent is to separate judgment from
/// persistence: GarageHUD records the truth; Steward interprets it. As the
/// product evolves this namespace will grow to encapsulate more sophisticated
/// analysis and advice, but early iterations intentionally keep the API thin to
/// avoid over‑engineering. Consumers of `Steward` should not need to know
/// anything about CloudKit, StoreKit, or SwiftUI—it simply computes values from
/// models.
public enum Steward {
    /// Returns a list of suggestions for the next steps on a given vehicle.
    ///
    /// Today this delegates directly to `BuildAdvisor` and returns its
    /// suggestions unchanged. Future iterations may incorporate other
    /// heuristics (e.g. maintenance schedules, reliability data, or market
    /// context) and return a richer type encapsulating confidence and
    /// provenance.
    /// - Parameter vehicle: The vehicle for which to compute suggestions.
    /// - Returns: An array of build suggestions ordered by perceived
    /// importance.
    public static func suggestions(for vehicle: Vehicle) -> [BuildAdvisor.Suggestion] {
        BuildAdvisor.suggestions(for: vehicle)
    }

    /// Provides the current horsepower estimate for the vehicle. This wraps
    /// `Vehicle.currentHorsepowerEstimate` to document that horsepower is
    /// considered an interpretation rather than a persisted fact; the
    /// underlying model chooses the latest dyno pull or factory rating.
    /// - Parameter vehicle: The vehicle being inspected.
    /// - Returns: The estimated wheel horsepower, if known.
    public static func currentHorsepower(for vehicle: Vehicle) -> Double? {
        vehicle.currentHorsepowerEstimate
    }

    /// Computes the estimated horsepower gain over the factory rating, if both
    /// values are available and the gain is positive. Negative or zero gains
    /// return `nil` to indicate that no improvement has been recorded.
    /// - Parameter vehicle: The vehicle being inspected.
    /// - Returns: The horsepower gained, or `nil` if unknown or non‑positive.
    public static func horsepowerGained(for vehicle: Vehicle) -> Double? {
        vehicle.horsepowerGainedOverStock
    }

    /// Returns the cost per horsepower gained over stock. If either the gain
    /// or the invested cost is unavailable this returns `nil`. This metric can
    /// help owners assess the efficiency of their modifications. A lower
    /// number indicates better value per horsepower.
    /// - Parameter vehicle: The vehicle being inspected.
    /// - Returns: Dollars spent per horsepower gained, or `nil` if undefined.
    public static func costPerHorsepower(for vehicle: Vehicle) -> Double? {
        vehicle.costPerHorsepowerGained
    }

    /// Returns the total amount invested in the build. This wraps
    /// `Vehicle.totalInvested` to emphasize that the number may come from a
    /// documented lump sum rather than a simple sum of parts. In the future
    /// Steward may adjust this figure for inflation or currency changes.
    /// - Parameter vehicle: The vehicle being inspected.
    /// - Returns: The amount invested, or zero if unknown.
    public static func totalInvested(for vehicle: Vehicle) -> Double {
        vehicle.totalInvested
    }
}