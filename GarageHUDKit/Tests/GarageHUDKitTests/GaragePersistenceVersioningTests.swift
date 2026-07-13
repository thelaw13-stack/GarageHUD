import XCTest
@testable import GarageHUDKit

/// TD-005: the local file is versioned and a corrupt file is never silently discarded. These
/// pin the current round-trip, legacy migration, forward-compat, and the unreadable case.
final class GaragePersistenceVersioningTests: XCTestCase {

    private func s2k() -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.parts = [Part(name: "Supercharger", category: .forcedInduction, cost: 5759.75)]
        v.drivetrain = .rwd
        return v
    }

    func testVersionedRoundTrip() throws {
        let data = try GaragePersistence.encode([s2k()])
        // The written document carries the schema version.
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\":\(GaragePersistence.currentSchemaVersion)"))

        guard case .ok(let loaded) = GaragePersistence.decode(data) else { return XCTFail("expected .ok") }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].parts.first?.cost, 5759.75)
        XCTAssertEqual(loaded[0].drivetrain, .rwd)
    }

    func testLegacyBareArrayMigrates() throws {
        // A pre-versioning file was a bare [Vehicle] array.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let legacy = try encoder.encode([s2k()])
        guard case .migratedLegacy(let loaded) = GaragePersistence.decode(legacy) else {
            return XCTFail("expected .migratedLegacy")
        }
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].make, "Honda")
    }

    func testEmptyFileIsEmptyNotUnreadable() {
        XCTAssertEqual(GaragePersistence.decode(Data()), .empty)
    }

    func testCorruptFileIsUnreadableNotDiscarded() {
        let garbage = Data("{ this is not valid garage json ]".utf8)
        XCTAssertEqual(GaragePersistence.decode(garbage), .unreadable)
    }

    func testForwardCompatNewerSchemaStillDecodesVehicles() throws {
        // A file written by a hypothetical newer version (higher schemaVersion) must still load
        // its vehicles rather than being treated as corrupt.
        let v = s2k()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let inner = try encoder.encode(v)
        let vehicleJSON = String(data: inner, encoding: .utf8)!
        let future = Data("{\"schemaVersion\":999,\"vehicles\":[\(vehicleJSON)]}".utf8)
        guard case .ok(let loaded) = GaragePersistence.decode(future) else { return XCTFail("expected .ok") }
        XCTAssertEqual(loaded.count, 1)
    }
}
