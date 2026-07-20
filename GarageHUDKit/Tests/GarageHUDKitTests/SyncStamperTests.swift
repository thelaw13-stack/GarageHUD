import XCTest
@testable import GarageHUDKit

/// W-065 — stamping what the owner actually changed.
///
/// The dangerous failures here are quiet ones: stamping things nobody edited (so the last device to
/// open the app wins every race), or stamping nothing (so the merge layer stays inert and looks
/// fine). Both are tested directly.
final class SyncStamperTests: XCTestCase {

    private let node = UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000A")!
    private let carID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-00000000000C")!
    private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    private func car() -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, nickname: "Fozzy",
                        garageSlot: 1, factoryHorsepower: 224)
        v.id = carID
        v.factoryPowerBasis = .factoryCrank
        return v
    }

    func testEditingAFieldStampsItsGroup() {
        var clock = SyncClock(node: node)
        let before = car()
        var after = before
        after.factoryHorsepower = 300

        let result = SyncStamper.stamping([after], against: [before], clock: &clock, now: at(1_000))
        XCTAssertFalse(result[0].stamp(for: .power).isZero, "the edited group must be stamped")
    }

    func testEditingAFieldDoesNotStampOtherGroups() {
        // The whole value of grouping is lost if one edit stamps everything: unrelated groups would
        // then win races they never took part in.
        var clock = SyncClock(node: node)
        let before = car()
        var after = before
        after.factoryHorsepower = 300

        let result = SyncStamper.stamping([after], against: [before], clock: &clock, now: at(1_000))
        XCTAssertTrue(result[0].stamp(for: .identity).isZero)
        XCTAssertTrue(result[0].stamp(for: .money).isZero)
        XCTAssertTrue(result[0].stamp(for: .status).isZero)
        XCTAssertTrue(result[0].stamp(for: .capability).isZero)
    }

    func testASaveThatChangesNothingAdvancesNoStamp() {
        // Otherwise every launch inflates stamps and the last device to open the app wins
        // regardless of who actually edited anything.
        var clock = SyncClock(node: node)
        let before = car()
        let result = SyncStamper.stamping([before], against: [before], clock: &clock, now: at(1_000))
        XCTAssertEqual(result, [before])
        for group in CoherenceGroup.allCases {
            XCTAssertTrue(result[0].stamp(for: group).isZero, "\(group) was stamped by a no-op save")
        }
    }

    func testRestampingIsStableAcrossRepeatedSaves() {
        // A stamped record must not look "changed" merely because it was stamped, or it restamps on
        // every save forever and the clock runs away.
        var clock = SyncClock(node: node)
        let before = car()
        var after = before
        after.factoryHorsepower = 300

        let once = SyncStamper.stamping([after], against: [before], clock: &clock, now: at(1_000))
        let twice = SyncStamper.stamping(once, against: once, clock: &clock, now: at(2_000))
        XCTAssertEqual(once, twice, "a second identical save must change nothing")
    }

    func testEditingOnePartStampsOnlyThatPart() {
        var clock = SyncClock(node: node)
        let turbo = UUID(), pump = UUID()
        var before = car()
        before.parts = [
            Part(id: turbo, name: "COBB 20G", category: .forcedInduction, cost: 1_200),
            Part(id: pump, name: "Fuel pump", category: .fueling, cost: 300),
        ]
        var after = before
        after.parts[1].cost = 350

        let result = SyncStamper.stamping([after], against: [before], clock: &clock, now: at(1_000))
        XCTAssertNil(result[0].parts.first { $0.id == turbo }?.stamp, "untouched part was stamped")
        XCTAssertNotNil(result[0].parts.first { $0.id == pump }?.stamp)
    }

    func testEditingMaintenanceStampsThatRecord() {
        var clock = SyncClock(node: node)
        let oil = UUID()
        var before = car()
        before.maintenance = [MaintenanceItem(id: oil, name: "Oil", intervalMonths: 6, lastServiced: at(0))]
        var after = before
        after.maintenance[0].lastServiced = at(9_000)

        let result = SyncStamper.stamping([after], against: [before], clock: &clock, now: at(1_000))
        XCTAssertNotNil(result[0].maintenance[0].stamp)
    }

    func testANewVehicleNeedsNoStamps() {
        // Its id is unique to this device, so there is nothing on the other side to resolve against.
        var clock = SyncClock(node: node)
        let fresh = car()
        let result = SyncStamper.stamping([fresh], against: [], clock: &clock, now: at(1_000))
        XCTAssertEqual(result, [fresh])
    }

    func testEachEditGetsADistinctIncreasingStamp() {
        var clock = SyncClock(node: node)
        var before = car()
        var after = before
        after.factoryHorsepower = 300
        after.purchasePrice = 9_000

        let result = SyncStamper.stamping([after], against: [before], clock: &clock, now: at(1_000))
        let power = result[0].stamp(for: .power), money = result[0].stamp(for: .money)
        XCTAssertNotEqual(power, money, "two groups stamped in one save must not collide")

        // And a later edit must order after both.
        before = result[0]
        var later = before
        later.nickname = "Foz"
        let second = SyncStamper.stamping([later], against: [before], clock: &clock, now: at(2_000))
        XCTAssertTrue(max(power, money) < second[0].stamp(for: .identity))
    }

    // MARK: The end-to-end property W-065 exists to deliver

    func testTwoDevicesEditingDifferentGroupsBothKeepTheirEdits() {
        let base = car()
        var macClock = SyncClock(node: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!)
        var phoneClock = SyncClock(node: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!)

        var macEdit = base
        macEdit.purchasePrice = 9_000
        let mac = SyncStamper.stamping([macEdit], against: [base], clock: &macClock, now: at(1_000))

        var phoneEdit = base
        phoneEdit.factoryHorsepower = 400
        let phone = SyncStamper.stamping([phoneEdit], against: [base], clock: &phoneClock, now: at(2_000))

        // Before W-065 one of these two edits was simply lost, whichever device pushed second.
        let merged = GarageMerge.adopt(mac, preservingAppendsFrom: phone)[0]
        XCTAssertEqual(merged.purchasePrice, 9_000, "the Mac's money edit was lost")
        XCTAssertEqual(merged.factoryHorsepower, 400, "the phone's power edit was lost")

        let other = GarageMerge.adopt(phone, preservingAppendsFrom: mac)[0]
        XCTAssertEqual(other.purchasePrice, merged.purchasePrice)
        XCTAssertEqual(other.factoryHorsepower, merged.factoryHorsepower)
    }
}
