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

    func testFutureSchemaIsRefusedInsteadOfDecodedAndLaterDowngraded() throws {
        // An older app cannot safely rewrite a future document: decoding known fields and then
        // saving schema v1 would discard every field it does not understand.
        let v = s2k()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let inner = try encoder.encode(v)
        let vehicleJSON = String(data: inner, encoding: .utf8)!
        let future = Data("{\"schemaVersion\":999,\"vehicles\":[\(vehicleJSON)]}".utf8)
        XCTAssertEqual(GaragePersistence.decode(future), .unsupportedVersion(999))
    }

    @MainActor
    func testStoreLeavesFutureSchemaFileByteForByteUntouched() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("future-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("garage.json")
        let future = Data("{\"schemaVersion\":999,\"vehicles\":[],\"futureTruth\":\"keep me\"}".utf8)
        try future.write(to: url)

        let store = GarageStore(fileURL: url, syncEnabled: false)

        XCTAssertEqual(store.unsupportedSchemaVersion, 999)
        XCTAssertEqual(try Data(contentsOf: url), future)
        XCTAssertTrue(store.vehicles.isEmpty)
    }
}
