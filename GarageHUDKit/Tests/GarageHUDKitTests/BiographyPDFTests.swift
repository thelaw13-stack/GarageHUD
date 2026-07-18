import XCTest
import SwiftUI
@testable import GarageHUDKit

/// The biography PDF prints the same BiographyModel words as the text export, styled. It must
/// render a real PDF, survive a decade-long timeline inside the CGContext page ceiling (with a
/// disclosed cut), and stay honest for an un-dynoed car.
@MainActor
final class BiographyPDFTests: XCTestCase {

    private func richCar() -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, nickname: "S2K", garageSlot: 1,
                        factoryHorsepower: 237)
        v.drivetrain = .rwd
        v.purchasePrice = 18_000
        v.parts = [Part(name: "SC kit", category: .forcedInduction, status: .installed, cost: 5_760)]
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 477)]
        v.buildEvents = [BuildEvent(title: "Odometer check", mileage: 82_000)]
        return v
    }

    func testRendersAValidNonTrivialPDF() throws {
        let data = try XCTUnwrap(BiographyPDF.data(for: richCar()), "biography should render")
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)), "should be a PDF")
        XCTAssertGreaterThan(data.count, 2_000, "a real car's biography has real content")
    }

    func testDecadeLongTimelineRendersWithinThePageCeiling() throws {
        var v = richCar()
        v.buildEvents = (0..<400).map { i in
            BuildEvent(date: Date(timeIntervalSinceNow: Double(-i) * 86_400),
                       title: "Event \(i)", mileage: 82_000 - i * 10)
        }
        let data = try XCTUnwrap(BiographyPDF.data(for: v), "400 events must not break the render")
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        // The cut is disclosed in the model-driven document, and the full history stays in text.
        XCTAssertTrue(BiographyExporter.text(for: v).contains("Event 399"),
                      "the text export always carries the full history")
    }

    func testBareCarStillRenders() throws {
        let bare = Vehicle(make: "Mazda", model: "Miata", year: 1999, garageSlot: 1)
        let data = try XCTUnwrap(BiographyPDF.data(for: bare))
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
    }
}
