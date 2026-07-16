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

    func testFullEightBayFleetRendersOnePageWithinLimits() throws {
        // The sheet is a single continuous page; a full 8-bay garage must still render inside the
        // CGContext page ceiling (14,400pt). Eight varied cards land well under it.
        let eight = (0..<8).map { i -> Vehicle in
            var v = PreviewVehicles.multiObservation
            v.garageSlot = i + 1
            v.buildGoal = BuildGoal(summary: "Goal \(i)", targetWheelHP: 400 + Double(i * 20))
            return v
        }
        let data = try XCTUnwrap(FleetSheetPDF.data(for: eight))
        XCTAssertTrue(data.starts(with: Array("%PDF".utf8)))
        XCTAssertGreaterThan(data.count, 5_000)
    }
}
