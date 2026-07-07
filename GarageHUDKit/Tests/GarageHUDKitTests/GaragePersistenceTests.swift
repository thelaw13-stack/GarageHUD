import XCTest
@testable import GarageHUDKit

/// TD-001 guardrail: whole-document sync + local persistence both depend on the vehicle
/// graph round-tripping losslessly through JSON. This locks that contract down.
final class GaragePersistenceTests: XCTestCase {
    func testVehicleGraphRoundTripsThroughJSON() throws {
        var vehicle = Vehicle(make: "Honda", model: "S2000", year: 2006, trim: "AP2",
                              nickname: "S2K", garageSlot: 1, factoryHorsepower: 237)
        vehicle.parts = [Part(name: "Supercharger", category: .forcedInduction,
                              brand: "Paxton", cost: 6000, notes: "NOVI 1200")]
        vehicle.notes = [Note(title: "Alignment", body: "-2.7 front camber")]
        vehicle.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 477, wheelTorque: 317)]
        vehicle.documentedTotalInvestment = 25_246.92

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode([vehicle])
        let restored = try decoder.decode([Vehicle].self, from: data)

        XCTAssertEqual(restored.count, 1)
        let r = restored[0]
        XCTAssertEqual(r.id, vehicle.id, "stable identity must survive a sync round-trip")
        XCTAssertEqual(r.nickname, "S2K")
        XCTAssertEqual(r.parts.first?.brand, "Paxton")
        XCTAssertEqual(r.parts.first?.cost, 6000)
        XCTAssertEqual(r.notes.first?.title, "Alignment")
        XCTAssertEqual(r.performanceRecords.first?.wheelTorque, 317)
        XCTAssertEqual(r.totalInvested, 25_246.92, accuracy: 0.001)
    }

    func testLiveCaptureRecordPreservesSamples() throws {
        let samples = [
            LiveMetrics(rpm: 3000, speedMph: 40, coolantTempF: 190, boostPsi: 5, throttlePercent: 50),
            LiveMetrics(rpm: 6500, speedMph: 90, coolantTempF: 205, boostPsi: 11, throttlePercent: 100)
        ]
        let record = PerformanceRecord(type: .boostLog, isFromLiveSession: true, capturedPoints: samples)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(PerformanceRecord.self, from: try encoder.encode(record))

        XCTAssertTrue(restored.isFromLiveSession)
        XCTAssertEqual(restored.capturedPoints.count, 2)
        XCTAssertEqual(restored.capturedPoints.last?.boostPsi, 11)
    }
}
