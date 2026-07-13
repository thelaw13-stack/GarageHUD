import XCTest
@testable import GarageHUDKit

/// Duplicate record ids (from a past import/merge) are healed at the source: the first keeps its id,
/// later collisions get fresh ones — so no collection can hard-crash a ForEach or confuse sheets.
final class DedupeRecordIDsTests: XCTestCase {
    func testReassignsDuplicateBuildEventIDs() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let shared = UUID()
        v.buildEvents = [BuildEvent(id: shared, title: "A"), BuildEvent(id: shared, title: "B")]
        XCTAssertTrue(v.dedupeRecordIDs())
        XCTAssertEqual(Set(v.buildEvents.map(\.id)).count, 2)
        XCTAssertEqual(v.buildEvents[0].id, shared)          // first occurrence keeps its id
        XCTAssertEqual(v.buildEvents.map(\.title), ["A", "B"])  // order + content preserved
    }

    func testHealsAcrossAllRecordCollections() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let p = UUID(), m = UUID()
        v.parts = [Part(id: p, name: "X", category: .engine), Part(id: p, name: "Y", category: .engine)]
        v.maintenance = [MaintenanceItem(id: m, name: "Oil", intervalMonths: 6, lastServiced: .now),
                         MaintenanceItem(id: m, name: "Filter", intervalMonths: 6, lastServiced: .now)]
        XCTAssertTrue(v.dedupeRecordIDs())
        XCTAssertEqual(Set(v.parts.map(\.id)).count, 2)
        XCTAssertEqual(Set(v.maintenance.map(\.id)).count, 2)
    }

    func testNoOpWhenAlreadyUnique() {
        var v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "A"), BuildEvent(title: "B")]
        XCTAssertFalse(v.dedupeRecordIDs())
    }

    func testPhotosAreUniqueAcrossTheWholeVehicleAndCoverSurvives() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let shared = UUID()
        let cover = Photo(id: shared, filename: "cover.jpg")
        v.photos = [cover]                                             // vehicle photo (the cover)
        v.buildEvents = [BuildEvent(title: "Dyno", photos: [Photo(id: shared, filename: "dyno.jpg")])]
        v.setCover(shared)                                            // cover points at the vehicle photo

        XCTAssertTrue(v.dedupeRecordIDs())
        // All photo ids across the vehicle are now unique — the gallery ForEach can't collide.
        let allIDs = v.allPhotos.map(\.id)
        XCTAssertEqual(Set(allIDs).count, allIDs.count)
        // The vehicle photo (visited first) kept its id, so the chosen cover still resolves.
        XCTAssertEqual(v.coverPhotoID, shared)
        XCTAssertEqual(v.heroPhoto?.filename, "cover.jpg")
    }

    func testChecklistTaskIDsAreHealed() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let dup = UUID()
        v.serviceStatus = ServiceStatus(isInService: true, reason: "build",
                                        checklist: [ServiceTask(id: dup, title: "A"),
                                                    ServiceTask(id: dup, title: "B")])
        XCTAssertTrue(v.dedupeRecordIDs())
        XCTAssertEqual(Set(v.serviceStatus.checklist.map(\.id)).count, 2)
    }
}
