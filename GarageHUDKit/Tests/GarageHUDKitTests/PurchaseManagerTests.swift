import XCTest
@testable import GarageHUDKit

final class PurchaseManagerTests: XCTestCase {
    func testInitialUnlockUsesStoredEntitlementWithoutDevelopmentOverride() {
        XCTAssertFalse(PurchaseManager.initialUnlockedState(
            storedUnlock: false,
            developmentForceUnlock: false))
        XCTAssertTrue(PurchaseManager.initialUnlockedState(
            storedUnlock: true,
            developmentForceUnlock: false))
    }

    func testInitialUnlockAllowsDevelopmentOverride() {
        XCTAssertTrue(PurchaseManager.initialUnlockedState(
            storedUnlock: false,
            developmentForceUnlock: true))
    }
}
