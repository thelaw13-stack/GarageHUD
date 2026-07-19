import XCTest
@testable import GarageHUDKit

/// The CloudKit garage payload is now a versioned `{ schemaVersion, vehicles }` document, the same
/// envelope as the local file — so a schema version travels with the synced graph and a future
/// non-additive change to the cloud model is safe. The pull must still accept a pre-versioning bare
/// array (records written by older builds), so introducing the envelope never drops a device's data.
final class CloudPayloadTests: XCTestCase {

    private func fleet() -> [Vehicle] {
        var s2k = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        s2k.purchasePrice = 18_000
        s2k.parts = [Part(name: "Coilovers", category: .suspension, status: .installed, cost: 1200)]
        return [s2k, Vehicle(make: "Subaru", model: "Forester", year: 2008, garageSlot: 2)]
    }

    func testPayloadIsVersionedAndRoundTrips() throws {
        let data = try CloudSyncManager.encodePayload(fleet())

        // The envelope carries a schemaVersion — not a bare array.
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["schemaVersion"] as? Int, GaragePersistence.currentSchemaVersion)

        let restored = try XCTUnwrap(CloudSyncManager.decodePayload(data))
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.first?.purchasePrice, 18_000)
        XCTAssertEqual(restored.first?.totalInvested, 1200)
    }

    func testPullStillAcceptsLegacyBareArrayFromOlderDevices() throws {
        // A record written before versioning: a bare [Vehicle] JSON array.
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let legacy = try encoder.encode(fleet())
        let restored = try XCTUnwrap(CloudSyncManager.decodePayload(legacy), "legacy cloud data must not be dropped")
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored.first?.model, "S2000")
    }

    func testUnreadableOrEmptyPayloadDecodesToNil() {
        XCTAssertNil(CloudSyncManager.decodePayload(Data("not json".utf8)))
        XCTAssertNil(CloudSyncManager.decodePayload(Data()))
    }

    func testFuturePayloadIsNotSilentlyDowngraded() throws {
        let current = try CloudSyncManager.encodePayload(fleet())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        object["schemaVersion"] = 999
        let future = try JSONSerialization.data(withJSONObject: object)
        XCTAssertNil(CloudSyncManager.decodePayload(future))
    }

    func testOnlyExplicitNotFoundPermitsInitialCloudSeed() {
        XCTAssertTrue(CloudSyncManager.PullResult.notFound.permitsInitialSeed)
        XCTAssertFalse(CloudSyncManager.PullResult.failed.permitsInitialSeed)
        XCTAssertFalse(CloudSyncManager.PullResult.unreadable.permitsInitialSeed)
        XCTAssertFalse(CloudSyncManager.PullResult.found(.init(vehicles: [], updatedAt: .distantPast)).permitsInitialSeed)
    }
}
