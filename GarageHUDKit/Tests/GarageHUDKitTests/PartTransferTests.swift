import XCTest
@testable import GarageHUDKit

/// Moving a part between vehicles — a real fleet workflow (e.g. pulling an amp from one build and
/// installing it in another). The part must keep its identity, leave the source, land on the
/// destination, and log a dated event on both cars.
@MainActor
final class PartTransferTests: XCTestCase {
    private func store(with vehicles: [Vehicle]) -> GarageStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transfer-\(UUID()).json")
        let s = GarageStore(fileURL: url, syncEnabled: false)
        s.vehicles = vehicles
        return s
    }

    func testMoveRelocatesPartAndLogsBothTimelines() {
        var fozzy = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, nickname: "Fozzy", garageSlot: 1)
        let tundra = Vehicle(make: "Toyota", model: "Tundra", year: 2021, nickname: "Tundra", garageSlot: 2)
        let amp = Part(name: "JL VX800/8i", category: .electronics, status: .installed)
        fozzy.parts = [amp]
        let s = store(with: [fozzy, tundra])

        XCTAssertTrue(s.moveParts(partID: amp.id, from: fozzy.id, to: tundra.id))

        let src = s.vehicles.first { $0.id == fozzy.id }!
        let dst = s.vehicles.first { $0.id == tundra.id }!
        XCTAssertFalse(src.parts.contains { $0.id == amp.id })
        XCTAssertEqual(dst.parts.first?.id, amp.id)                    // same identity preserved
        XCTAssertTrue(src.buildEvents.contains { $0.title.contains("Removed") })
        XCTAssertTrue(dst.buildEvents.contains { $0.title.contains("Installed") })
    }

    /// The moved part is re-dated to the transfer moment. Carrying the source car's install date
    /// over fabricated the destination's history — a 2021-dated turbo landing next to 2026-dated
    /// injectors read as years of "forced induction ran ahead of the fueling" on a car that never
    /// ran boost unfueled.
    func testMoveRedatesInstallSoDestinationHistoryIsHonest() {
        var civic = Vehicle(make: "Honda", model: "Civic", year: 2000, garageSlot: 1)
        var s2k = Vehicle(make: "Honda", model: "S2000", year: 2004, garageSlot: 2)
        let turbo = Part(name: "T3 turbo", category: .forcedInduction, status: .installed,
                         installDate: Date(timeIntervalSinceNow: -2_000 * 86_400))
        civic.parts = [turbo]
        s2k.parts = [Part(name: "Injectors", category: .fueling, status: .installed,
                          installDate: Date(timeIntervalSinceNow: -30 * 86_400))]
        let s = store(with: [civic, s2k])
        XCTAssertTrue(s.moveParts(partID: turbo.id, from: civic.id, to: s2k.id))

        let dst = s.vehicles.first { $0.id == s2k.id }!
        let moved = dst.parts.first { $0.id == turbo.id }!
        XCTAssertGreaterThan(moved.installDate!, Date(timeIntervalSinceNow: -60),
                             "install date must be the transfer moment, not the source car's history")
        XCTAssertFalse(Steward.observe(dst).contains { $0.ruleID == "sequence.fiAheadOfFueling" },
                       "no fabricated boost-before-fueling history on the destination")
    }

    func testMoveToSameVehicleIsNoOp() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let p = Part(name: "Coilovers", category: .suspension, status: .installed)
        v.parts = [p]
        let s = store(with: [v])
        XCTAssertFalse(s.moveParts(partID: p.id, from: v.id, to: v.id))
        XCTAssertEqual(s.vehicles.first?.parts.count, 1)              // untouched
    }
}
