import XCTest
@testable import GarageHUDKit

/// Regression for the seed/old-data decode bug: synthesized Decodable does NOT apply property
/// defaults for missing keys, so models must decode tolerantly. Pins that a record missing
/// newer keys still decodes with defaults — and that the bundled seed decodes.
final class SeedDecodeCheck: XCTestCase {

    func testRecordMissingNewerKeysDecodesWithDefaults() throws {
        let json = """
        [{
          "id":"11111111-1111-1111-1111-111111111111",
          "make":"Honda","model":"S2000","year":2006,"garageSlot":1,
          "parts":[{"id":"22222222-2222-2222-2222-222222222222","name":"Turbo","category":"Forced Induction","status":"Installed"}]
        }]
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let vehicles = try dec.decode([Vehicle].self, from: Data(json.utf8))
        XCTAssertEqual(vehicles.count, 1)
        let v = vehicles[0]
        XCTAssertEqual(v.parts.count, 1)
        XCTAssertFalse(v.parts[0].flaggedForRebuild)
        XCTAssertEqual(v.drivetrain, .unknown)
        XCTAssertEqual(v.factoryPowerBasis, .factoryCrank)
        XCTAssertFalse(v.serviceStatus.isInService)
        XCTAssertTrue(v.confirmedStockSystems.isEmpty)
    }

    func testBundledSeedDecodes() throws {
        let seedURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("GarageHUD-iOS/GarageHUDApp/garage_seed.json")
        guard let data = try? Data(contentsOf: seedURL) else {
            throw XCTSkip("seed not found at \(seedURL.path)")
        }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let vehicles = try dec.decode([Vehicle].self, from: data)
        XCTAssertFalse(vehicles.isEmpty)
        XCTAssertGreaterThan(vehicles[0].parts.count, 10)
    }
}
