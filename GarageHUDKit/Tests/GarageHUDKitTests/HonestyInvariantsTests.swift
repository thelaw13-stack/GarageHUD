import XCTest
@testable import GarageHUDKit

/// Honesty is the whole pitch: the app must never state an unmeasured number as measured, never
/// present a crank figure as a wheel one, and never count planned or asserted-away things as facts.
/// These grew out of an adversarial audit — each one is an attack that must keep failing.
final class HonestyInvariantsTests: XCTestCase {

    /// A dyno logged with NO value is not a measurement. It must not dress the factory (crank) figure
    /// up as "measured whp", nor shadow an earlier real dyno. (This was a live leak on the build sheet
    /// and fleet sheet — both shareable — until gated on `hasMeasuredPower`.)
    func testNumberlessDynoIsNeverLabeledMeasured() {
        var v = Vehicle(make: "Mazda", model: "MX-5", year: 2016, garageSlot: 1, factoryHorsepower: 155)
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: nil)]

        XCTAssertFalse(v.hasMeasuredPower, "a dyno with no number is not a measurement")
        XCTAssertNil(v.measuredWheelHorsepower)

        let sheet = BuildSheetExporter.text(for: v)
        XCTAssertTrue(sheet.contains("155 hp (factory rated)"), sheet)
        XCTAssertFalse(sheet.localizedCaseInsensitiveContains("155 whp"), "must not claim a measured wheel figure")
        XCTAssertFalse(sheet.localizedCaseInsensitiveContains("measured"), sheet)
    }

    /// A real earlier dyno must not be hidden by a later numberless one.
    func testEarlierRealDynoIsNotShadowedByALaterNumberlessOne() {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1, factoryHorsepower: 237)
        v.performanceRecords = [
            PerformanceRecord(date: .init(timeIntervalSince1970: 1_000), type: .dyno, wheelHorsepower: 300),
            PerformanceRecord(date: .init(timeIntervalSince1970: 2_000), type: .dyno, wheelHorsepower: nil),
        ]
        XCTAssertTrue(v.hasMeasuredPower)
        XCTAssertEqual(v.measuredWheelHorsepower, 300)
        XCTAssertEqual(v.currentHorsepowerEstimate, 300)   // the real 300, not the 237 crank fallback
    }

    /// A physically installed part outranks an owner's stale "confirmed stock" claim — the app resolves
    /// the contradiction toward the hardware that's actually there, rather than holding both.
    func testInstalledPartOverridesConfirmedStock() {
        var v = Vehicle(make: "Subaru", model: "WRX", year: 2015, garageSlot: 1, factoryHorsepower: 268)
        v.confirmedStockSystems = [.fueling]
        v.parts = [Part(name: "Injectors", category: .fueling, status: .installed)]
        XCTAssertEqual(v.knowledge(of: .fueling), .confirmedPresent)
    }

    /// A planned (wishlist) part is intent, not a fact. It must never read as a supported/covered
    /// system — only as an open item with a plan against it.
    func testPlannedPartIsNotCountedAsCovered() {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 1, factoryHorsepower: 224)
        v.parts = [
            Part(name: "Big turbo", category: .forcedInduction, status: .installed),
            Part(name: "Injectors", category: .fueling, status: .wishlist),
        ]
        let fueling = Steward.assess(v)?.subsystems.first { $0.label.localizedCaseInsensitiveContains("fuel") }
        XCTAssertNotEqual(fueling?.status, .supported, "a planned part is not coverage")
    }
}
