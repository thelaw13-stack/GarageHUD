import XCTest
@testable import GarageHUDKit

/// The card hero photo prefers the vehicle's own first photo, then falls back to the most recent
/// build-event photo, so any car with photography shows a face on the garage grid.
final class HeroPhotoTests: XCTestCase {
    private func photo(_ name: String) -> Photo { Photo(filename: "\(name).jpg") }
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    func testPrefersVehiclePhoto() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        let hero = photo("hero")
        v.photos = [hero]
        v.buildEvents = [BuildEvent(title: "Dyno", photos: [photo("dyno")])]
        XCTAssertEqual(v.heroPhoto?.filename, "hero.jpg")
    }

    func testFallsBackToMostRecentEventPhoto() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1)
        v.buildEvents = [
            BuildEvent(date: daysAgo(100), title: "Old", photos: [photo("old")]),
            BuildEvent(date: daysAgo(2), title: "New", photos: [photo("new")]),
        ]
        XCTAssertEqual(v.heroPhoto?.filename, "new.jpg")
    }

    func testNilWhenNoPhotosAnywhere() {
        var v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1)
        v.buildEvents = [BuildEvent(title: "Acquired")]
        XCTAssertNil(v.heroPhoto)
    }
}
