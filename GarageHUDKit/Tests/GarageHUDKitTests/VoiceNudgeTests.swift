import XCTest
@testable import GarageHUDKit

/// The "get a better voice" nudge must earn its place: only when the device has just the robotic
/// default, the natural cloud voice is off, and the owner hasn't dismissed it — and dismissal sticks.
final class VoiceNudgeTests: XCTestCase {

    func testShowsOnlyWhenRoboticOnlyAndCloudOffAndNotDismissed() {
        XCTAssertTrue(VoiceNudge.shouldShow(onlyDefaultVoiceInstalled: true, cloudVoiceEnabled: false, dismissed: false))
    }

    func testHiddenWhenABetterVoiceIsAlreadyInstalled() {
        XCTAssertFalse(VoiceNudge.shouldShow(onlyDefaultVoiceInstalled: false, cloudVoiceEnabled: false, dismissed: false))
    }

    func testHiddenWhenCloudVoiceIsOn() {
        // Cloud voice already sounds human, so the on-device quality is moot — don't nag.
        XCTAssertFalse(VoiceNudge.shouldShow(onlyDefaultVoiceInstalled: true, cloudVoiceEnabled: true, dismissed: false))
    }

    func testHiddenOnceDismissed() {
        XCTAssertFalse(VoiceNudge.shouldShow(onlyDefaultVoiceInstalled: true, cloudVoiceEnabled: false, dismissed: true))
    }

    func testDismissalPersistsAndIsScopedToItsOwnDefaults() {
        let d = UserDefaults(suiteName: "VoiceNudgeTests-\(UUID().uuidString)")!
        XCTAssertFalse(VoiceNudge.isDismissed(d))
        VoiceNudge.markDismissed(d)
        XCTAssertTrue(VoiceNudge.isDismissed(d))
    }
}
