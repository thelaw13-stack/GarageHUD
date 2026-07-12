import XCTest
@testable import GarageHUDKit

/// The data-honesty nudge should fire only when undated parts are actually holding the
/// timeline back — not on a small or well-dated build.
final class StewardDataConfidenceTests: XCTestCase {

    private func part(_ name: String, dated: Bool) -> Part {
        Part(name: name, category: .engine, status: .installed,
             installDate: dated ? .now : nil)
    }

    func testFiresWhenManyInstalledPartsLackDates() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = (1...6).map { part("Part \($0)", dated: $0 > 3) } // 3 of 6 undated = 50%
        let nudge = Steward.observe(v).first { $0.statement.localizedCaseInsensitiveContains("dating a few more parts") }
        XCTAssertNotNil(nudge)
        XCTAssertEqual(nudge?.tone, .informational)
    }

    func testSilentWhenBuildIsWellDated() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = (1...6).map { part("Part \($0)", dated: $0 > 1) } // only 1 of 6 undated
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("dating a few more parts") })
    }

    func testSilentOnSmallBuild() {
        var v = Vehicle(make: "Test", model: "Car", year: 2020, garageSlot: 1)
        v.parts = [part("A", dated: false), part("B", dated: false)] // under the floor
        XCTAssertFalse(Steward.observe(v).contains { $0.statement.localizedCaseInsensitiveContains("dating a few more parts") })
    }
}
