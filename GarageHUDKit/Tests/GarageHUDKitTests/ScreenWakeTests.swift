import XCTest
@testable import GarageHUDKit

/// W-063 — field-found 2026-07-19: the phone slept while a session was measuring, so the dials the
/// owner was standing in the driveway to watch went dark. The hold must follow session state, and
/// must let go the moment the session isn't live — a permanently awake screen is its own bug.
final class ScreenWakeTests: XCTestCase {

    func testStaysAwakeWhileMeasuring() {
        XCTAssertTrue(ScreenWake.shouldStayAwake(sessionRunning: true, connection: .polling))
    }

    func testStaysAwakeThroughBringUpBeforeAnyFrameArrives() {
        // Scanning and handshaking are exactly when the owner is watching progress.
        XCTAssertTrue(ScreenWake.shouldStayAwake(sessionRunning: true, connection: nil))
        for state: OBDConnectionState in [.scanning, .connecting, .discoveringServices,
                                          .discoveringCharacteristics, .resetting, .configuring, .ready] {
            XCTAssertTrue(ScreenWake.shouldStayAwake(sessionRunning: true, connection: state),
                          "should hold wake during \(state)")
        }
    }

    func testStaysAwakeWhileDegradedOrReconnecting() {
        // Values going stale or a link being re-established is when the owner most needs to see the
        // screen — releasing here would hide the recovery.
        XCTAssertTrue(ScreenWake.shouldStayAwake(sessionRunning: true, connection: .degraded))
        XCTAssertTrue(ScreenWake.shouldStayAwake(sessionRunning: true, connection: .reconnecting))
    }

    func testReleasesWhenNoSessionIsRunning() {
        // The whole failure mode to avoid: a hold that outlives the session.
        XCTAssertFalse(ScreenWake.shouldStayAwake(sessionRunning: false, connection: nil))
        XCTAssertFalse(ScreenWake.shouldStayAwake(sessionRunning: false, connection: .polling))
        XCTAssertFalse(ScreenWake.shouldStayAwake(sessionRunning: false, connection: .disconnected))
    }

    func testReleasesWhenTheLinkIsDisconnectedEvenIfTheSessionThinksItIsRunning() {
        // Covers the error path: the adapter drops but the owner hasn't pressed Stop yet.
        XCTAssertFalse(ScreenWake.shouldStayAwake(sessionRunning: true, connection: .disconnected))
    }

    func testOnlyPollingCountsAsLiveButWakeIsBroaderThanLive() {
        // Guards the deliberate asymmetry: "live" is strictly .polling (values may be called
        // measured), while wake covers the whole engaged session. If someone later collapses these
        // two ideas, this fails.
        XCTAssertTrue(OBDConnectionState.polling.isLive)
        XCTAssertFalse(OBDConnectionState.ready.isLive)
        XCTAssertTrue(ScreenWake.shouldStayAwake(sessionRunning: true, connection: .ready))
    }
}
