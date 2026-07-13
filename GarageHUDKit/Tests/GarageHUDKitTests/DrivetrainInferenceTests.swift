import XCTest
@testable import GarageHUDKit

/// Drivetrain auto-populates from a vehicle's identifiers: explicit drive markers (4x4, AWD, 2WD…)
/// win, then well-known models, and it stays `.unknown` when genuinely ambiguous rather than guessing.
final class DrivetrainInferenceTests: XCTestCase {
    func testExplicitFourAndTwoWheelMarkers() {
        XCTAssertEqual(Drivetrain.inferred(make: "Toyota", model: "Tundra", trim: "SR5 4x4"), .fourWD)
        XCTAssertEqual(Drivetrain.inferred(make: "Ford", model: "F-150", trim: "XLT 4WD"), .fourWD)
        XCTAssertEqual(Drivetrain.inferred(make: "Toyota", model: "Tacoma", trim: "2WD"), .twoWD)
        XCTAssertEqual(Drivetrain.inferred(make: "Chevrolet", model: "Silverado", trim: "2x4"), .twoWD)
    }

    func testBrandDriveSystems() {
        XCTAssertEqual(Drivetrain.inferred(make: "Audi", model: "S4", trim: "quattro"), .awd)
        XCTAssertEqual(Drivetrain.inferred(make: "BMW", model: "X3", trim: "xDrive"), .awd)
        XCTAssertEqual(Drivetrain.inferred(make: "Mercedes", model: "C300", trim: "4MATIC"), .awd)
    }

    func testKnownModelsInTheFleet() {
        XCTAssertEqual(Drivetrain.inferred(make: "Honda", model: "S2000"), .rwd)
        XCTAssertEqual(Drivetrain.inferred(make: "Subaru", model: "Forester XT"), .awd)
        XCTAssertEqual(Drivetrain.inferred(make: "Volkswagen", model: "Baja Bug"), .rwd)
    }

    func testAmbiguousTruckStaysUnknown() {
        // No 4x4/2wd trim → we can't know the layout from make/model alone; don't guess.
        XCTAssertEqual(Drivetrain.inferred(make: "Toyota", model: "Tundra", trim: "SR5"), .unknown)
        XCTAssertEqual(Drivetrain.inferred(make: "RAM", model: "1500"), .unknown)
    }

    func testNewCasesAreSelectableAndHaveDistinctLoss() {
        XCTAssertTrue(Drivetrain.allCases.contains(.fourWD))
        XCTAssertTrue(Drivetrain.allCases.contains(.twoWD))
        XCTAssertGreaterThan(Drivetrain.fourWD.typicalLossFraction, Drivetrain.twoWD.typicalLossFraction)
    }
}
