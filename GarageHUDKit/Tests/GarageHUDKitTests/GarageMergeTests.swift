import XCTest
@testable import GarageHUDKit

/// W-054 — the sync bridge: adopting a remote document must not drop append-only records the
/// local device holds. The headline scenario is the one live hardware just made real: a pull
/// captured on the car's phone must survive the Mac pushing a spec edit.
final class GarageMergeTests: XCTestCase {

    private func car(_ id: UUID, name: String = "Fozzy") -> Vehicle {
        var v = Vehicle(id: id, make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.nickname = name
        return v
    }

    private func pull(at date: Date = .now) -> PullReport {
        PullReport(startedAt: date, endedAt: date.addingTimeInterval(8), feedLabel: "OBD-II Adapter",
                   rpmStart: 2500, rpmPeak: 6100, rpmEnd: 6000, boostPeakPsi: 15.2,
                   boostBreachedCeiling: false, boostCeilingPsi: 18,
                   onTargetFraction: 0.9, overTargetFraction: 0.05, underTargetFraction: 0.05,
                   coolantStartF: 190, coolantPeakF: 201, coolantDeltaF: 11,
                   sampleCount: 140, measuredBoostFraction: 1.0, confidence: .strong)
    }

    /// THE scenario: driveway pull on the phone, spec edit on the Mac, Mac pushes first.
    func testDrivewayPullSurvivesRemoteAdoption() {
        let id = UUID()
        var local = car(id)
        local.pullReports = [pull()]
        local.buildEvents = [BuildEvent(title: "Pull captured: 2500→6100 rpm")]

        var remote = car(id)
        remote.factoryHorsepower = 224   // the Mac's spec edit — remote is "newer"

        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertEqual(merged[0].factoryHorsepower, 224, "the adopting side's scalar edit wins")
        XCTAssertEqual(merged[0].pullReports.count, 1, "the phone's pull is NOT lost")
        XCTAssertEqual(merged[0].buildEvents.count, 1, "nor its biography event")
    }

    func testBothSidesNotesUnionWithoutDuplicates() {
        let id = UUID()
        let shared = Note(title: "Shared", body: "on both sides")
        var local = car(id); local.notes = [shared, Note(title: "Phone-only", body: "")]
        var remote = car(id); remote.notes = [shared, Note(title: "Mac-only", body: "")]
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertEqual(merged[0].notes.count, 3, "union by id — shared note not duplicated")
    }

    func testSameIDEditRaceStaysLWW() {
        let id = UUID(); let eventID = UUID()
        var local = car(id)
        local.buildEvents = [BuildEvent(id: eventID, title: "Oil change (phone wording)")]
        var remote = car(id)
        remote.buildEvents = [BuildEvent(id: eventID, title: "Oil change (Mac wording)")]
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertEqual(merged[0].buildEvents.count, 1)
        XCTAssertEqual(merged[0].buildEvents[0].title, "Oil change (Mac wording)",
                       "an edit race on the same record is still last-writer-wins — documented")
    }

    func testVehicleSetIsStillAdoptSideWins() {
        let kept = UUID(), remoteOnly = UUID(), localOnly = UUID()
        let merged = GarageMerge.adopt([car(kept), car(remoteOnly, name: "New on Mac")],
                                       preservingAppendsFrom: [car(kept), car(localOnly, name: "Phone-only")])
        XCTAssertEqual(Set(merged.map(\.id)), [kept, remoteOnly],
                       "no whole-vehicle resurrection: the adopting document's car list stands")
    }

    // MARK: - Tombstones (TD-001) — a deletion survives adoption instead of being resurrected

    /// The reversal of the old documented trade-off: a record deleted on the Mac (with a tombstone)
    /// stays deleted, even though the phone still holds it.
    func testTombstonedRecordIsSuppressedNotResurrected() {
        let id = UUID(); let noteID = UUID()
        var local = car(id)
        local.notes = [Note(id: noteID, title: "Deleted on the Mac, still on the phone", body: "")]
        var remote = car(id)                       // Mac deleted the note...
        remote.deletedRecordIDs = [noteID]         // ...and recorded the tombstone
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertTrue(merged[0].notes.isEmpty, "delete-wins: the tombstoned note does not come back")
        XCTAssertTrue(merged[0].deletedRecordIDs.contains(noteID), "the tombstone is carried forward")
    }

    /// The direction that matters for the driveway: a deletion made on the phone must suppress the
    /// copy the incoming (adopting) document still carries.
    func testLocalDeletionPropagatesToAdoptedCopy() {
        let id = UUID(); let recID = UUID()
        var local = car(id)
        local.deletedRecordIDs = [recID]           // phone deleted a dyno record
        var remote = car(id)
        remote.performanceRecords = [PerformanceRecord(id: recID, type: .dyno, wheelHorsepower: 300)]
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertTrue(merged[0].performanceRecords.isEmpty,
                      "the phone's delete suppresses the record the adopted document still holds")
    }

    func testTombstonesUnionAcrossBothSides() {
        let id = UUID(); let a = UUID(); let b = UUID()
        var local = car(id);  local.deletedRecordIDs = [a]
        var remote = car(id); remote.deletedRecordIDs = [b]
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertEqual(merged[0].deletedRecordIDs, [a, b], "both devices' deletions are remembered")
    }

    /// Delete-wins is deliberate: a tombstone beats the other side's stale copy of the same id.
    func testDeleteWinsOverAConcurrentHeldCopy() {
        let id = UUID(); let pullID = UUID()
        var local = car(id)
        local.pullReports = [pull()]; local.pullReports[0].id = pullID
        var remote = car(id)
        remote.deletedRecordIDs = [pullID]
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertTrue(merged[0].pullReports.isEmpty, "a tombstone beats a still-held copy")
    }

    /// The honest residual limit: an *absence* with no tombstone is not a deletion — it's exactly the
    /// append-preservation case, so the record is kept. (A client too old to write tombstones can't
    /// have its deletions honored; only full event history closes that — the TD-001 direction.)
    func testUntombstonedAbsenceStillPreservesTheAppend() {
        let id = UUID()
        var local = car(id)
        local.notes = [Note(title: "Phone-only capture", body: "")]
        let remote = car(id)                        // simply never had it — NOT a recorded delete
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertEqual(merged[0].notes.count, 1, "no tombstone → treated as an append to preserve")
    }

    // MARK: - Deletion helpers record tombstones, and they survive Codable

    func testDeleteHelpersRecordTombstones() {
        var v = car(UUID())
        let dyno = PerformanceRecord(type: .dyno, wheelHorsepower: 300)
        let note = Note(title: "n", body: "")
        let photo = Photo(filename: "p.jpg")
        v.performanceRecords = [dyno]; v.notes = [note]; v.photos = [photo]

        v.deletePerformanceRecord(dyno.id)
        v.deleteNotes([note.id])
        v.deletePhoto(photo.id)

        XCTAssertTrue(v.performanceRecords.isEmpty && v.notes.isEmpty && v.photos.isEmpty)
        XCTAssertEqual(v.deletedRecordIDs, [dyno.id, note.id, photo.id])
    }

    func testTombstonesRoundTripThroughCodableAndDefaultEmpty() throws {
        var v = car(UUID()); v.deletedRecordIDs = [UUID(), UUID()]
        let data = try JSONEncoder().encode(v)
        let back = try JSONDecoder().decode(Vehicle.self, from: data)
        XCTAssertEqual(back.deletedRecordIDs, v.deletedRecordIDs, "tombstones persist and sync")

        // A document written before tombstones existed decodes to an empty set, not a failure.
        let legacy = Data(#"{"id":"\#(UUID().uuidString)","make":"Subaru","model":"WRX","year":2015}"#.utf8)
        let old = try JSONDecoder().decode(Vehicle.self, from: legacy)
        XCTAssertTrue(old.deletedRecordIDs.isEmpty)
    }
}
