import XCTest
@testable import GarageHUDKit

/// ADR-0005 tests 3–10 — the merge itself.
///
/// The point of these is not that a newer edit wins; that part is easy. It is that a merge can never
/// assemble a vehicle that existed on no device, and that legacy documents behave exactly as they do
/// today.
final class StampedMergeTests: XCTestCase {

    private let macNode = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let phoneNode = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private func at(_ s: TimeInterval) -> Date { Date(timeIntervalSince1970: s) }

    /// Both sides must be the SAME car: GarageMerge matches vehicles by id, so a fresh UUID per
    /// call would mean two unrelated vehicles and no merge at all.
    private let carID = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!

    private func car() -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, nickname: "Fozzy",
                        garageSlot: 1, factoryHorsepower: 224)
        v.id = carID
        v.factoryPowerBasis = .factoryCrank
        v.drivetrain = .awd
        return v
    }

    // MARK: Test 3 — the coherence case this design exists for

    func testConcurrentPowerEditsNeverProduceACrankFigureLabelledAsWheel() {
        var mac = SyncClock(node: macNode), phone = SyncClock(node: phoneNode)

        // Mac edits the horsepower, leaving the basis at crank.
        var macSide = car()
        macSide.factoryHorsepower = 300
        macSide.setStamp(mac.stamp(now: at(1_000)), for: .power)

        // Phone concurrently relabels the basis as a wheel figure, leaving hp at the old 224.
        var phoneSide = car()
        phoneSide.factoryPowerBasis = .measuredWheel
        phoneSide.setStamp(phone.stamp(now: at(2_000)), for: .power)

        // Field-level LWW would take hp=300 from the Mac and basis=wheel from the phone: a crank
        // dyno number wearing a wheel label, a car that existed on neither device.
        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]

        let heldTogether =
            (merged.factoryHorsepower == 300 && merged.factoryPowerBasis == .factoryCrank) ||
            (merged.factoryHorsepower == 224 && merged.factoryPowerBasis == .measuredWheel)
        XCTAssertTrue(heldTogether,
                      "power group split: hp=\(String(describing: merged.factoryHorsepower)) basis=\(merged.factoryPowerBasis)")

        // The phone's edit is newer, so the whole group is the phone's state.
        XCTAssertEqual(merged.factoryPowerBasis, .measuredWheel)
        XCTAssertEqual(merged.factoryHorsepower, 224)
    }

    // MARK: Test 4 — money coherence

    func testMoneyFieldsCannotBeMergedIntoACombinationNeitherOwnerEntered() {
        var mac = SyncClock(node: macNode), phone = SyncClock(node: phoneNode)

        var macSide = car()
        macSide.purchasePrice = 9_000
        macSide.documentedTotalInvestment = 14_857
        macSide.setStamp(mac.stamp(now: at(1_000)), for: .money)

        var phoneSide = car()
        phoneSide.purchasePrice = 11_500
        phoneSide.documentedTotalInvestment = 20_000
        phoneSide.setStamp(phone.stamp(now: at(2_000)), for: .money)

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        let asEntered =
            (merged.purchasePrice == 9_000 && merged.documentedTotalInvestment == 14_857) ||
            (merged.purchasePrice == 11_500 && merged.documentedTotalInvestment == 20_000)
        XCTAssertTrue(asEntered, "money group split into a pairing neither device ever held")
    }

    func testAnUneditedGroupIsNotDraggedAlongByAnEditedOne() {
        // Independence between groups: a newer power edit must not pull the other side's identity.
        var mac = SyncClock(node: macNode), phone = SyncClock(node: phoneNode)

        var macSide = car()
        macSide.nickname = "Fozzy"
        macSide.setStamp(mac.stamp(now: at(5_000)), for: .identity)

        var phoneSide = car()
        phoneSide.nickname = "WRONG"
        phoneSide.factoryHorsepower = 400
        phoneSide.setStamp(phone.stamp(now: at(9_000)), for: .power)   // power only

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.nickname, "Fozzy", "identity followed an unrelated power edit")
        XCTAssertEqual(merged.factoryHorsepower, 400)
    }

    // MARK: Tests 5 & 6 — parts

    func testEditsToDifferentPartsOnTwoDevicesBothSurvive() {
        var mac = SyncClock(node: macNode), phone = SyncClock(node: phoneNode)
        let turboID = UUID(), pumpID = UUID()

        var macSide = car()
        macSide.parts = [
            Part(id: turboID, name: "COBB 20G (Mac edit)", category: .forcedInduction, cost: 1_400),
            Part(id: pumpID, name: "Fuel pump", category: .fueling, cost: 300),
        ]
        macSide.parts[0].stamp = mac.stamp(now: at(1_000))

        var phoneSide = car()
        phoneSide.parts = [
            Part(id: turboID, name: "COBB 20G", category: .forcedInduction, cost: 1_200),
            Part(id: pumpID, name: "Fuel pump (phone edit)", category: .fueling, cost: 350),
        ]
        phoneSide.parts[1].stamp = phone.stamp(now: at(2_000))

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.parts.count, 2)
        // Each device's edit survives on its own part — the whole point of per-record stamps.
        XCTAssertEqual(merged.parts.first { $0.id == turboID }?.cost, 1_400)
        XCTAssertEqual(merged.parts.first { $0.id == pumpID }?.cost, 350)
    }

    func testConcurrentEditsToTheSamePartOrderByStamp() {
        var mac = SyncClock(node: macNode), phone = SyncClock(node: phoneNode)
        let id = UUID()

        var macSide = car()
        macSide.parts = [Part(id: id, name: "Mac", category: .fueling, cost: 100)]
        macSide.parts[0].stamp = mac.stamp(now: at(1_000))

        var phoneSide = car()
        phoneSide.parts = [Part(id: id, name: "Phone", category: .fueling, cost: 200)]
        phoneSide.parts[0].stamp = phone.stamp(now: at(3_000))

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.parts.count, 1)
        XCTAssertEqual(merged.parts[0].cost, 200, "the newer stamped edit should win")
    }

    func testADeletedPartStaysDeletedEvenWhenTheOtherSideEditedIt() {
        // Tombstones must still beat a stamped edit — delete-wins is deliberate (W-056).
        var phone = SyncClock(node: phoneNode)
        let id = UUID()

        var macSide = car()
        macSide.parts = []
        macSide.deletedRecordIDs = [id]

        var phoneSide = car()
        phoneSide.parts = [Part(id: id, name: "Edited after deletion elsewhere", category: .fueling)]
        phoneSide.parts[0].stamp = phone.stamp(now: at(9_999))

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertTrue(merged.parts.isEmpty, "a tombstone must outrank a newer edit of the same record")
    }

    func testMaintenanceMergesPerRecordToo() {
        var phone = SyncClock(node: phoneNode)
        let oilID = UUID(), beltID = UUID()

        var macSide = car()
        macSide.maintenance = [MaintenanceItem(id: oilID, name: "Oil", intervalMonths: 6, lastServiced: at(0))]

        var phoneSide = car()
        phoneSide.maintenance = [
            MaintenanceItem(id: oilID, name: "Oil (serviced)", intervalMonths: 6, lastServiced: at(8_000)),
            MaintenanceItem(id: beltID, name: "Timing belt", intervalMonths: 60, lastServiced: at(0)),
        ]
        phoneSide.maintenance[0].stamp = phone.stamp(now: at(8_000))

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.maintenance.count, 2, "the phone-only item must survive")
        XCTAssertEqual(merged.maintenance.first { $0.id == oilID }?.lastServiced, at(8_000))
    }

    // MARK: Test 7 — legacy behaviour must not change

    func testUnstampedDocumentsMergeExactlyAsBefore() {
        // Two legacy sides: no stamps anywhere. Adopt-side-wins, unchanged.
        var macSide = car()
        macSide.factoryHorsepower = 300
        macSide.nickname = "Mac"
        macSide.parts = [Part(name: "Mac part", category: .fueling, cost: 100)]

        var phoneSide = car()
        phoneSide.factoryHorsepower = 999
        phoneSide.nickname = "Phone"

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.factoryHorsepower, 300, "adopting side must still win when nothing is stamped")
        XCTAssertEqual(merged.nickname, "Mac")
        XCTAssertEqual(merged.parts.count, 1)
    }

    func testAStampedEditBeatsAnUnstampedLegacyValue() {
        var phone = SyncClock(node: phoneNode)
        var macSide = car()                       // legacy: no stamps
        macSide.factoryHorsepower = 224

        var phoneSide = car()                     // upgraded client made a deliberate edit
        phoneSide.factoryHorsepower = 300
        phoneSide.setStamp(phone.stamp(now: at(1_000)), for: .power)

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.factoryHorsepower, 300)
    }

    // MARK: Test 8 — round-trip

    func testStampsSurviveTheVersionedEnvelope() throws {
        var phone = SyncClock(node: phoneNode)
        var v = car()
        v.setStamp(phone.stamp(now: at(1_234)), for: .power)
        v.parts = [Part(name: "Turbo", category: .forcedInduction)]
        v.parts[0].stamp = phone.stamp(now: at(1_235))
        // Maintenance is checked too: Vehicle, Part and MaintenanceItem all hand-write their
        // decoders, so each one drops a new field independently unless it is added by hand. Testing
        // only two of the three is how the third stays broken.
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: at(0))]
        v.maintenance[0].stamp = phone.stamp(now: at(1_236))

        let data = try GaragePersistence.encode([v])
        guard case .ok(let decoded) = GaragePersistence.decode(data) else {
            return XCTFail("stamped document must decode as .ok")
        }
        XCTAssertEqual(decoded[0].stamp(for: CoherenceGroup.power), v.stamp(for: CoherenceGroup.power))
        XCTAssertEqual(decoded[0].parts[0].stamp, v.parts[0].stamp)
        XCTAssertEqual(decoded[0].maintenance[0].stamp, v.maintenance[0].stamp)
    }

    // MARK: Test 9 — the existing guarantees are untouched

    func testAppendOnlyRecordsAndTombstonesStillBehave() {
        var macSide = car()
        var phoneSide = car()
        let keptID = UUID(), killedID = UUID()
        phoneSide.buildEvents = [BuildEvent(id: keptID, title: "Driveway pull")]
        phoneSide.notes = [Note(id: killedID, title: "deleted elsewhere")]
        macSide.deletedRecordIDs = [killedID]

        let merged = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        XCTAssertEqual(merged.buildEvents.count, 1, "W-054 append preservation")
        XCTAssertTrue(merged.notes.isEmpty, "W-056 tombstone suppression")
    }

    // MARK: Test 10 — the one that catches a wrong design rather than a wrong implementation

    func testMergingIsOrderIndependentForStampedState() {
        var mac = SyncClock(node: macNode), phone = SyncClock(node: phoneNode)
        let sharedPart = UUID()

        var macSide = car()
        macSide.factoryHorsepower = 300
        macSide.setStamp(mac.stamp(now: at(1_000)), for: .power)
        macSide.purchasePrice = 9_000
        macSide.setStamp(mac.stamp(now: at(4_000)), for: .money)
        macSide.parts = [Part(id: sharedPart, name: "Mac", category: .fueling, cost: 100)]
        macSide.parts[0].stamp = mac.stamp(now: at(1_500))

        var phoneSide = car()
        phoneSide.factoryHorsepower = 400
        phoneSide.setStamp(phone.stamp(now: at(2_000)), for: .power)
        phoneSide.purchasePrice = 11_000
        phoneSide.setStamp(phone.stamp(now: at(3_000)), for: .money)
        phoneSide.parts = [Part(id: sharedPart, name: "Phone", category: .fueling, cost: 250)]
        phoneSide.parts[0].stamp = phone.stamp(now: at(2_500))

        let a = GarageMerge.adopt([macSide], preservingAppendsFrom: [phoneSide])[0]
        let b = GarageMerge.adopt([phoneSide], preservingAppendsFrom: [macSide])[0]

        // Whichever device runs the merge, the resolved state must agree — otherwise the two devices
        // diverge permanently and each believes it is correct.
        XCTAssertEqual(a.factoryHorsepower, b.factoryHorsepower)
        XCTAssertEqual(a.factoryPowerBasis, b.factoryPowerBasis)
        XCTAssertEqual(a.purchasePrice, b.purchasePrice)
        XCTAssertEqual(a.parts.first { $0.id == sharedPart }?.cost,
                       b.parts.first { $0.id == sharedPart }?.cost)

        // And the winners are the genuinely newer edits, not just consistent nonsense.
        XCTAssertEqual(a.factoryHorsepower, 400)   // phone's power edit is newer
        XCTAssertEqual(a.purchasePrice, 9_000)     // mac's money edit is newer
    }
}
