import XCTest
@testable import GarageHUDKit

/// W-073 torque/weight slice. Torque is display-only; weight seeds power-to-weight, so the monotonic
/// rule must carry through the division — a guessed weight cannot produce a confident ratio.
final class TorqueWeightProvenanceTests: XCTestCase {

    private func car(hp: Double?, hpProv: Provenance,
                     weight: Double?, weightProv: Provenance) -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: hp)
        v.factoryHorsepowerProvenance = hpProv
        v.factoryWeightLbs = weight
        v.factoryWeightProvenance = weightProv
        v.drivetrain = .rwd
        return v
    }

    func testAGuessedWeightDragsThePowerToWeightRatioToEstimated() {
        let v = car(hp: 240, hpProv: .sourced, weight: 2800, weightProv: .estimated)
        XCTAssertNotNil(v.powerToWeight)
        XCTAssertEqual(v.powerToWeightProvenance, .estimated, "the ratio is only as strong as the weight")
    }

    func testAGuessedPowerAlsoDragsTheRatioDown() {
        let v = car(hp: 240, hpProv: .estimated, weight: 2800, weightProv: .sourced)
        XCTAssertEqual(v.powerToWeightProvenance, .estimated)
    }

    func testAMeasuredPowerWithSourcedWeightKeepsTheRatioStrong() {
        var v = car(hp: nil, hpProv: .unspecified, weight: 2800, weightProv: .sourced)
        v.performanceRecords = [PerformanceRecord(date: .now, type: .dyno, wheelHorsepower: 300)]
        XCTAssertTrue(v.hasMeasuredPower)
        XCTAssertEqual(v.currentPowerProvenance, .measured)
        XCTAssertEqual(v.powerToWeightProvenance, .sourced, "weakest of measured + sourced is sourced")
    }

    func testLegacyInputsLeaveTheRatioUnspecified() {
        // Migration promise: two unmarked values produce an unspecified ratio, rendered as today.
        let v = car(hp: 240, hpProv: .unspecified, weight: 2800, weightProv: .unspecified)
        XCTAssertEqual(v.powerToWeightProvenance, .unspecified)
    }

    func testNoRatioMeansUnknownProvenance() {
        let v = car(hp: 240, hpProv: .sourced, weight: nil, weightProv: .unknown)
        XCTAssertNil(v.powerToWeight)
        XCTAssertEqual(v.powerToWeightProvenance, .unknown)
    }

    func testTorqueAndWeightProvenanceSurviveARoundTrip() throws {
        let v = car(hp: 240, hpProv: .estimated, weight: 2800, weightProv: .estimated)
        var w = v; w.factoryTorque = 160; w.factoryTorqueProvenance = .sourced
        let data = try GaragePersistence.encode([w])
        guard case .ok(let decoded) = GaragePersistence.decode(data) else { return XCTFail("decode") }
        XCTAssertEqual(decoded[0].factoryTorqueProvenance, .sourced)
        XCTAssertEqual(decoded[0].factoryWeightProvenance, .estimated)
    }
}
