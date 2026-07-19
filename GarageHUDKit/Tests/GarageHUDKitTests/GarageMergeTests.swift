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

    /// The documented trade-off, pinned so it's a decision and not a surprise: add-wins without
    /// tombstones means a record deleted remotely but still held locally comes back. Visible
    /// and re-deletable — unlike a silently lost pull. Event sync with tombstones (TD-001,
    /// promoted) is the real fix.
    func testDeletedRemoteRecordResurrects_KnownTradeoff() {
        let id = UUID()
        var local = car(id)
        local.notes = [Note(title: "Deleted on the Mac, still on the phone", body: "")]
        let remote = car(id)   // Mac deleted the note
        let merged = GarageMerge.adopt([remote], preservingAppendsFrom: [local])
        XCTAssertEqual(merged[0].notes.count, 1, "add-wins: the note returns (documented trade-off)")
    }
}
