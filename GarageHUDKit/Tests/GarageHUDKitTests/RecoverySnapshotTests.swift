import XCTest
@testable import GarageHUDKit

/// Preserved garage files are only safety if the owner can find and use them. These cover the
/// discovery + restore API behind the Recovery UI: listing, an undoable restore (the current
/// garage is preserved first), and refusing to touch anything for an unreadable file.
@MainActor
final class RecoverySnapshotTests: XCTestCase {

    private func freshStore() -> (store: GarageStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovery-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = GarageStore(fileURL: dir.appendingPathComponent("garage.json"), syncEnabled: false)
        return (store, dir)
    }

    private func vehicle(_ name: String, slot: Int) -> Vehicle {
        Vehicle(make: "Honda", model: name, year: 2004, garageSlot: slot)
    }

    /// Plant an older pre-versioning snapshot to prove recovery remains backward-compatible.
    private func plantLegacySnapshot(_ vehicles: [Vehicle], in dir: URL, name: String) throws {
        let snapshots = dir.appendingPathComponent("Conflict Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(vehicles).write(to: snapshots.appendingPathComponent(name))
    }

    func testListsPlantedSnapshotsWithVehicleCounts() throws {
        let (store, dir) = freshStore()
        try plantLegacySnapshot([vehicle("S2000", slot: 1), vehicle("Civic", slot: 2)],
                                in: dir, name: "garage-conflict-local-t1.json")
        let listed = store.recoverySnapshots
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.kind, .syncConflict)
        XCTAssertEqual(listed.first?.vehicleCount, 2)
        try? FileManager.default.removeItem(at: dir)
    }

    func testRestoreReplacesGarageAndPreservesCurrentFirst() throws {
        let (store, dir) = freshStore()
        store.vehicles = [vehicle("Tundra", slot: 1)]
        try plantLegacySnapshot([vehicle("S2000", slot: 1), vehicle("Civic", slot: 2)],
                                in: dir, name: "garage-conflict-local-t1.json")

        let snapshot = store.recoverySnapshots.first!
        XCTAssertTrue(store.restore(from: snapshot))
        XCTAssertEqual(store.vehicles.count, 2, "garage replaced by the snapshot's contents")
        XCTAssertEqual(store.vehicles.map(\.model).sorted(), ["Civic", "S2000"])

        // The pre-restore copy of the 1-car garage now exists — the restore is itself undoable.
        let preRestore = store.recoverySnapshots.first { $0.kind == .preRestore }
        XCTAssertNotNil(preRestore)
        XCTAssertEqual(preRestore?.vehicleCount, 1)
        let preservedData = try Data(contentsOf: preRestore!.url)
        guard case .ok(let preserved) = GaragePersistence.decode(preservedData) else {
            return XCTFail("new safety snapshots must use the current versioned document")
        }
        XCTAssertEqual(preserved.map(\.model), ["Tundra"])
        XCTAssertTrue(store.restore(from: preRestore!))
        XCTAssertEqual(store.vehicles.map(\.model), ["Tundra"], "restored the restore")
        try? FileManager.default.removeItem(at: dir)
    }

    func testUnreadableSnapshotIsRefusedAndUntouched() throws {
        let (store, dir) = freshStore()
        store.vehicles = [vehicle("Tundra", slot: 1)]
        let snapshots = dir.appendingPathComponent("Conflict Snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let bad = snapshots.appendingPathComponent("garage-conflict-local-bad.json")
        try Data("not json at all".utf8).write(to: bad)

        let listed = store.recoverySnapshots.first!
        XCTAssertNil(listed.vehicleCount, "unreadable file advertises no restorable contents")
        XCTAssertFalse(store.restore(from: listed))
        XCTAssertEqual(store.vehicles.map(\.model), ["Tundra"], "nothing touched on a failed restore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: bad.path), "the preserved file is kept")
        try? FileManager.default.removeItem(at: dir)
    }

    func testDeleteRemovesTheFile() throws {
        let (store, dir) = freshStore()
        try plantLegacySnapshot([vehicle("S2000", slot: 1)], in: dir,
                                name: "garage-conflict-local-t1.json")
        let snapshot = store.recoverySnapshots.first!
        store.deleteRecoverySnapshot(snapshot)
        XCTAssertTrue(store.recoverySnapshots.isEmpty)
        try? FileManager.default.removeItem(at: dir)
    }
}
