import XCTest
@testable import GarageHUDKit

/// The owner can choose which photo represents a car. heroPhoto honors that choice, falls back to
/// the default when it's cleared, and self-heals if the chosen photo is later deleted.
final class CoverPhotoTests: XCTestCase {
    private func photo(_ name: String) -> Photo { Photo(filename: "\(name).jpg") }

    func testChosenCoverWins() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let first = photo("first"); let pick = photo("pick")
        v.photos = [first, pick]
        XCTAssertEqual(v.heroPhoto?.filename, "first.jpg")   // default before a choice
        v.setCover(pick.id)
        XCTAssertEqual(v.heroPhoto?.filename, "pick.jpg")
    }

    func testCoverCanBeAnEventPhoto() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        let vp = photo("vehicle"); let ep = photo("event")
        v.photos = [vp]
        v.buildEvents = [BuildEvent(title: "Dyno", photos: [ep])]
        v.setCover(ep.id)
        XCTAssertEqual(v.heroPhoto?.filename, "event.jpg")
    }

    func testClearingCoverReturnsToDefault() {
        var v = Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 1)
        let a = photo("a"); let b = photo("b")
        v.photos = [a, b]
        v.setCover(b.id)
        v.setCover(nil)
        XCTAssertEqual(v.heroPhoto?.filename, "a.jpg")
    }

    func testStaleCoverFallsBackWhenPhotoDeleted() {
        var v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        let a = photo("a"); let gone = photo("gone")
        v.photos = [a, gone]
        v.setCover(gone.id)
        v.photos.removeAll { $0.id == gone.id }               // cover photo deleted out from under it
        XCTAssertEqual(v.heroPhoto?.filename, "a.jpg")        // heals to the default, not nil
    }
}
