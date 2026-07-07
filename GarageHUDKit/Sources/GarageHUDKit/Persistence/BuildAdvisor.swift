import Foundation

/// Rule-based "what's next" suggestions from installed-part category gaps plus the
/// wishlist. Not a real recommendation engine — just enough pattern matching to
/// surface common supporting-mod gaps and turn the wishlist into concrete next steps.
public enum BuildAdvisor {
    public struct Suggestion: Identifiable {
        public let id = UUID()
        public let text: String
        public let isWishlistItem: Bool
    }

    static func suggestions(for vehicle: Vehicle) -> [Suggestion] {
        var results: [Suggestion] = []
        let installed = Set(vehicle.parts.filter { $0.status == .installed }.map(\.category))

        if installed.contains(.forcedInduction) {
            if !installed.contains(.fueling) {
                results.append(Suggestion(text: "Forced induction is installed but no fueling upgrades are logged — verify injectors/pump can support the added airflow.", isWishlistItem: false))
            }
            if !installed.contains(.cooling) {
                results.append(Suggestion(text: "No cooling upgrades logged alongside forced induction — added heat load usually calls for a bigger radiator or oil cooler.", isWishlistItem: false))
            }
            if !installed.contains(.electronics) {
                results.append(Suggestion(text: "No tune/ECU logged — confirm the car's been professionally tuned for the current power level.", isWishlistItem: false))
            }
        }

        if installed.contains(.suspension) && !installed.contains(.brakes) {
            results.append(Suggestion(text: "Suspension's been upgraded but brakes haven't — stock brakes are a common weak point once handling improves.", isWishlistItem: false))
        }

        let wishlist = vehicle.parts.filter { $0.status == .wishlist }.sorted { $0.name < $1.name }
        for part in wishlist.prefix(4) {
            let detail = part.notes.isEmpty ? "" : " — \(part.notes)"
            results.append(Suggestion(text: "Planned: \(part.name)\(detail)", isWishlistItem: true))
        }

        return results
    }
}
