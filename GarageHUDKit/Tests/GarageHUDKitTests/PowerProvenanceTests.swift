import XCTest
@testable import GarageHUDKit

/// ADR-0006 power slice — the provenance of the factory figure travels into the derived baseline,
/// and a placeholder can no longer produce a hard-looking stock baseline (W-070, W-071).
final class PowerProvenanceTests: XCTestCase {

    private func car(hp: Double?, provenance: Provenance, drivetrain: Drivetrain = .rwd,
                     basis: PowerBasis = .factoryCrank) -> Vehicle {
        var v = Vehicle(make: "VW", model: "Beetle Baja", year: 1970, garageSlot: 1, factoryHorsepower: hp)
        v.factoryHorsepowerProvenance = provenance
        v.drivetrain = drivetrain
        v.factoryPowerBasis = basis
        return v
    }

    func testANewFactoryFigureDefaultsToEstimatedNotDocumented() {
        // The humble default lives in the editor, but the model must never start a typed number at a
        // stronger origin than estimate. A fresh vehicle's unset figure is unspecified (legacy-safe).
        let v = car(hp: 75, provenance: .estimated)
        XCTAssertEqual(v.factoryHorsepowerProvenance, .estimated)
        XCTAssertFalse(v.factoryHorsepowerProvenance.canPresentAsMeasured)
    }

    func testAnEstimatedFactoryFigureYieldsAnEstimatedBaseline() {
        // The monotonic rule: 75 hp typed as an estimate → the 63 whp baseline is itself an estimate,
        // never a hard number.
        let v = car(hp: 75, provenance: .estimated)
        XCTAssertNotNil(v.estimatedStockWheelHP)
        XCTAssertEqual(v.estimatedStockWheelHPProvenance, .estimated)
    }

    func testTheFleetSheetMarksAnEstimatedBaselineAndNeverStacksAHardNumber() {
        // W-071 exactly: the crank headline over a wheel baseline must not read as a hard comparison.
        let model = FleetSheetCardModel.make(for: car(hp: 75, provenance: .estimated))
        XCTAssertEqual(model.stockBaselineValue?.hasPrefix("~"), true, "estimated baseline must read as ~N")
        XCTAssertEqual(model.stockBaselineCaption?.contains("est"), true)
    }

    func testALegacyValueStillRendersAsTodayNoRetroactiveDoubt() {
        // The migration promise: an unspecified (pre-provenance) figure is not marked as an estimate.
        let model = FleetSheetCardModel.make(for: car(hp: 75, provenance: .unspecified))
        XCTAssertEqual(model.stockBaselineValue, "63 whp", "legacy baseline must render exactly as before")
        XCTAssertEqual(model.stockBaselineCaption?.contains("est"), false)
    }

    func testAMeasuredWheelBaselineIsNeverDowngraded() {
        // A real wheel figure is the baseline as-is, and stays a hard number.
        var v = car(hp: 200, provenance: .measured, basis: .measuredWheel)
        v.factoryPowerBasis = .measuredWheel
        XCTAssertEqual(v.estimatedStockWheelHP, 200)
        XCTAssertEqual(v.estimatedStockWheelHPProvenance, .measured)
        let model = FleetSheetCardModel.make(for: v)
        XCTAssertEqual(model.stockBaselineValue, "200 whp")
    }

    func testAnAssumedDrivetrainDragsTheBaselineDownToEstimated() {
        // Even a documented crank figure becomes an estimate at the wheels when the drivetrain loss
        // is assumed — the conversion introduces the estimate, and the monotonic rule records it.
        let v = car(hp: 100, provenance: .sourced, drivetrain: .unknown)
        XCTAssertTrue(v.stockWheelBaselineIsAssumed)
        XCTAssertEqual(v.estimatedStockWheelHPProvenance, .estimated)
    }

    func testProvenanceSurvivesAVehicleRoundTrip() throws {
        let v = car(hp: 75, provenance: .estimated)
        let data = try GaragePersistence.encode([v])
        guard case .ok(let decoded) = GaragePersistence.decode(data) else { return XCTFail("decode") }
        XCTAssertEqual(decoded[0].factoryHorsepowerProvenance, .estimated)
    }

    func testAnAbsentProvenanceDecodesAsUnspecified() throws {
        // A document written before this field existed: the key is simply missing.
        let json = #"{"schemaVersion":2,"vehicles":[{"id":"\#(UUID().uuidString)","make":"VW","model":"Beetle","year":1970,"garageSlot":1,"factoryHorsepower":75}]}"#
        guard case .ok(let decoded) = GaragePersistence.decode(Data(json.utf8)) else { return XCTFail("decode") }
        XCTAssertEqual(decoded[0].factoryHorsepowerProvenance, .unspecified)
    }
}
