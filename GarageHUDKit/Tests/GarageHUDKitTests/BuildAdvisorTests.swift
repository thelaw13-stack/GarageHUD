import XCTest
@testable import GarageHUDKit

/// TD-002: the advisor's rule set is easy to break silently; pin the core rules.
final class BuildAdvisorTests: XCTestCase {
    func testForcedInductionWithoutFuelingWarns() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1)
        vehicle.parts = [Part(name: "Turbo Kit", category: .forcedInduction, status: .installed)]
        let suggestions = BuildAdvisor.suggestions(for: vehicle)
        XCTAssertTrue(suggestions.contains { $0.text.localizedCaseInsensitiveContains("fueling") && !$0.isWishlistItem })
    }

    func testSuspensionWithoutBrakesWarns() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1)
        vehicle.parts = [Part(name: "Coilovers", category: .suspension, status: .installed)]
        let suggestions = BuildAdvisor.suggestions(for: vehicle)
        XCTAssertTrue(suggestions.contains { $0.text.localizedCaseInsensitiveContains("brake") })
    }

    func testWishlistPartsSurfaceAsSuggestions() {
        var vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1)
        vehicle.parts = [Part(name: "Big Brake Kit", category: .brakes, status: .wishlist)]
        let suggestions = BuildAdvisor.suggestions(for: vehicle)
        XCTAssertTrue(suggestions.contains { $0.isWishlistItem && $0.text.contains("Big Brake Kit") })
    }

    func testEmptyBuildProducesNoFalseWarnings() {
        let vehicle = Vehicle(make: "X", model: "Y", year: 2020, garageSlot: 1)
        XCTAssertTrue(BuildAdvisor.suggestions(for: vehicle).isEmpty)
    }
}
