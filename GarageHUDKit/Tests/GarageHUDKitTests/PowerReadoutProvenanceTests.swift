import XCTest
@testable import GarageHUDKit

/// W-074 — the origin marking must be visible on the surface where a value is edited, not only on the
/// exported fleet sheet. These pin the in-place wording the Specs screen reads.
final class PowerReadoutProvenanceTests: XCTestCase {

    private func baja(hp: Double?, provenance: Provenance) -> Vehicle {
        var v = Vehicle(make: "VW", model: "Beetle Baja", year: 1970, garageSlot: 1, factoryHorsepower: hp)
        v.factoryHorsepowerProvenance = provenance
        v.drivetrain = .rwd
        return v
    }

    func testATypedFactoryFigureNamesItselfAnEstimateInPlace() {
        XCTAssertEqual(baja(hp: 63, provenance: .estimated).factoryPowerReadoutQualifier, "estimate")
    }

    func testALegacyFigureKeepsNeutralFactoryWording() {
        // Migration promise on-screen too: an unspecified value is not relabelled a guess.
        XCTAssertEqual(baja(hp: 63, provenance: .unspecified).factoryPowerReadoutQualifier, "factory")
    }

    func testDocumentedAndMeasuredNameTheirOrigin() {
        XCTAssertEqual(baja(hp: 63, provenance: .sourced).factoryPowerReadoutQualifier, "documented")
        XCTAssertEqual(baja(hp: 63, provenance: .measured).factoryPowerReadoutQualifier, "measured")
    }

    func testTheBaselineReadsAsAnEstimateInPlaceWhenItIsOne() {
        // The number that misled on the fleet sheet, now honest on the Specs screen too.
        let display = baja(hp: 63, provenance: .estimated).stockWheelBaselineDisplay
        XCTAssertEqual(display?.hasPrefix("~"), true)
    }

    func testALegacyBaselineIsNotMarkedAnEstimate() {
        XCTAssertEqual(baja(hp: 63, provenance: .unspecified).stockWheelBaselineDisplay?.hasPrefix("~"), false)
    }

    func testNoFactoryFigureMeansNoBaselineToShow() {
        XCTAssertNil(baja(hp: nil, provenance: .unknown).stockWheelBaselineDisplay)
    }
}
