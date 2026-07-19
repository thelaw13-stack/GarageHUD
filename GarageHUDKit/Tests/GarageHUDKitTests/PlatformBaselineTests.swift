import XCTest
@testable import GarageHUDKit

/// The live limits must fit the car, not a flat number typed once. Grounded in researched
/// per-platform data (see PlatformBaseline / docs/STEWARD_THRESHOLDS.md), verified against Tim's
/// actual four cars.
final class PlatformBaselineTests: XCTestCase {

    private func s2k() -> Vehicle {   // supercharged AP2
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, trim: "AP2", garageSlot: 1, factoryHorsepower: 237)
        v.parts = [Part(name: "Kraftwerks supercharger", category: .forcedInduction, status: .installed)]
        return v
    }
    private func fozzy() -> Vehicle { // factory turbo
        Vehicle(make: "Subaru", model: "Forester XT", year: 2008, garageSlot: 2, factoryHorsepower: 224)
    }
    private func tundra() -> Vehicle { // NA V8
        Vehicle(make: "Toyota", model: "Tundra", year: 2021, garageSlot: 3, factoryHorsepower: 381)
    }
    private func baja() -> Vehicle {   // air-cooled
        Vehicle(make: "Volkswagen", model: "Baja", year: 1971, garageSlot: 4, factoryHorsepower: 60)
    }

    func testBoostCautionIsSourcedPerPlatform_notFlat18() {
        XCTAssertEqual(s2k().defaultBoostCautionPsi, 13, "supercharged S2000 — Kraftwerks band, not 18")
        XCTAssertEqual(fozzy().defaultBoostCautionPsi, 17, "EJ turbo — stock TD04 safe edge")
        XCTAssertNil(tundra().defaultBoostCautionPsi, "NA V8 — boost isn't a signal")
        XCTAssertNil(baja().defaultBoostCautionPsi, "NA air-cooled — no boost")
    }

    func testAirCooledCarHasNoCoolantLimit() {
        let env = OperatingEnvelope.default(for: baja())
        XCTAssertNil(env.coolantCautionF, "air-cooled — no coolant to measure")
        XCTAssertNil(env.coolantCriticalF)
        // Liquid-cooled cars keep their coolant limits.
        XCTAssertEqual(OperatingEnvelope.default(for: tundra()).coolantCautionF, 215)
        XCTAssertEqual(OperatingEnvelope.default(for: s2k()).coolantCriticalF, 235)
    }

    /// The real proof: even fed a hot coolant reading, an air-cooled car produces no coolant
    /// observation — because it has no coolant limit to cross.
    func testAirCooledCarNeverEmitsACoolantObservation() {
        let hot = LiveTelemetryFrame(
            coolantTempF: TimedMeasurement(260, source: .obdAdapter, at: Date()),
            connectionState: .polling, capturedAt: Date())
        let bajaObs = Steward.observe(frame: hot, for: baja())
        XCTAssertFalse(bajaObs.contains { $0.ruleID.hasPrefix("live.coolant") },
                       "an air-cooled engine must never be told its (nonexistent) coolant is hot")
        // A liquid-cooled car with the same reading DOES get the observation.
        let tundraObs = Steward.observe(frame: hot, for: tundra())
        XCTAssertTrue(tundraObs.contains { $0.ruleID.hasPrefix("live.coolant") })
    }

    func testUnknownBoostedPlatformFallsBackToConservativeGeneric() {
        var v = Vehicle(make: "Nissan", model: "240SX", year: 1995, garageSlot: 1, factoryHorsepower: 155)
        v.parts = [Part(name: "GT2871 turbo", category: .forcedInduction, status: .installed)]
        XCTAssertNil(v.platformBaseline, "not in the catalog")
        XCTAssertEqual(v.defaultBoostCautionPsi, PlatformBaseline.genericBoostedCautionPsi)
    }

    func testPreOBD2CarHasNoLiveTelemetry() {
        // OBD-II mandated on US cars in 1996. The air-cooled '71 Baja has no port at all.
        XCTAssertFalse(baja().supportsOBD2, "a 1971 air-cooled VW can't do live OBD telemetry")
        XCTAssertTrue(s2k().supportsOBD2)     // 2006
        XCTAssertTrue(fozzy().supportsOBD2)   // 2008
        XCTAssertTrue(tundra().supportsOBD2)  // 2021
        // A pre-1996 liquid-cooled car is also out.
        XCTAssertFalse(Vehicle(make: "Honda", model: "Civic", year: 1991, garageSlot: 1).supportsOBD2)
    }

    func testEveryCatalogEntryCitesASource() {
        for entry in PlatformBaseline.catalog {
            XCTAssertFalse(entry.source.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(entry.id) must cite where its numbers came from")
        }
    }
}
