import XCTest
import SwiftUI
@testable import GarageHUDKit

@MainActor
final class FleetSheetTests: XCTestCase {

    private var fleet: [Vehicle] {
        var normal = PreviewVehicles.normal
        normal.buildGoal = BuildGoal(summary: "Reliable street, keep it streetable", targetWheelHP: 550)
        return [normal, PreviewVehicles.incomplete, PreviewVehicles.outOfService, PreviewVehicles.multiObservation]
    }

    func testRendersAValidNonTrivialPDF() throws {
        let data = try XCTUnwrap(FleetSheetPDF.data(for: fleet), "fleet sheet should render")
        // A real PDF, not an empty fallback.
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)), "should be a PDF")
        XCTAssertGreaterThan(data.count, 3_000, "a four-car sheet should have real content")
    }

    func testEmptyFleetStillRenders() throws {
        let data = try XCTUnwrap(FleetSheetPDF.data(for: []))
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
    }
}
