import XCTest
@testable import GarageHUDKit

/// The biography is the whole story, exportable — and it holds the same honesty line as every
/// other shareable document: figures graded by evidence, planned money framed as planned, three
/// ownership money facts never conflated, provenance printed.
final class BiographyExporterTests: XCTestCase {

    private func day(_ offset: Int) -> Date { Date(timeIntervalSinceNow: Double(offset) * 86_400) }

    private func s2k() -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, nickname: "S2K", garageSlot: 1,
                        factoryHorsepower: 237)
        v.drivetrain = .rwd
        v.purchasePrice = 18_000
        v.parts = [Part(name: "SC kit", category: .forcedInduction, status: .installed,
                        installDate: day(-400), cost: 5_760),
                   Part(name: "Wilwood BBK", category: .brakes, status: .wishlist, cost: 1_800)]
        v.performanceRecords = [PerformanceRecord(date: day(-100), type: .dyno, wheelHorsepower: 477,
                                                  location: "Church Automotive")]
        v.maintenance = [MaintenanceItem(name: "Oil change", intervalMonths: 6, lastServiced: day(-90))]
        v.buildEvents = [BuildEvent(date: day(-30), title: "Odometer check", mileage: 82_000)]
        _ = v.markMaintenanceDone(v.maintenance[0].id, cost: 85)
        return v
    }

    func testBiographyTellsTheWholeStoryHonestly() {
        let v = s2k()
        let bio = BiographyExporter.text(for: v)

        XCTAssertTrue(bio.contains("VEHICLE BIOGRAPHY"))
        XCTAssertTrue(bio.contains("477 whp (measured)"), "power graded by the dyno")
        XCTAssertTrue(bio.contains("Church Automotive"), "the measurement names its dyno")
        XCTAssertTrue(bio.contains("$1,800 planned"), "wishlist money framed as planned")
        XCTAssertTrue(bio.contains("Purchase price: $18,000"))
        XCTAssertTrue(bio.contains("Maintenance spend: $85"))
        XCTAssertTrue(bio.split(separator: "\n").contains { $0.contains("Oil change") && $0.contains("$85") },
                      "service record carries its cost")
        XCTAssertTrue(bio.contains("82,000 mi"), "odometer from the record")
        XCTAssertTrue(bio.contains("WHERE THESE NUMBERS COME FROM"), "provenance appendix present")
    }

    func testUnDynoedCarNeverReadsMeasuredInTheBiography() {
        var v = s2k()
        v.performanceRecords = []
        let bio = BiographyExporter.text(for: v)
        XCTAssertTrue(bio.contains("237 hp (factory rated)"))
        XCTAssertFalse(bio.contains("whp (measured)"))
    }

    func testFileIsNamedForTheVehicle() {
        XCTAssertEqual(BiographyExporter.file(for: s2k()).fileName, "S2K biography")
    }
}
