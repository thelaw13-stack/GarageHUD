import Foundation

/// Whether the screen should be held awake during a live session.
///
/// Field-found 2026-07-19 (W-063): the phone followed its normal idle timer while a session was
/// measuring, so the dials the owner was standing in the driveway to watch went dark. Nothing in
/// the app ever requested wake.
///
/// The decision is a pure function of *session state* rather than view lifetime, so the hold is
/// released the moment a session really ends — a screen left permanently awake is its own bug, and
/// one the owner pays for in battery.
public enum ScreenWake {

    /// Hold the screen awake only while a session is genuinely engaged.
    ///
    /// - `sessionRunning`: the owner started a session and hasn't stopped it.
    /// - `connection`: the adapter lifecycle, or nil for the simulated feed / before the first frame.
    ///
    /// A running session with no frame yet still holds wake — scanning and handshaking are exactly
    /// when the owner is watching progress. A `.disconnected` link releases it: nothing is live, so
    /// there is nothing to watch, and that covers the error case as well as a clean stop.
    public static func shouldStayAwake(sessionRunning: Bool, connection: OBDConnectionState?) -> Bool {
        guard sessionRunning else { return false }
        guard let connection else { return true }
        return connection != .disconnected
    }
}
