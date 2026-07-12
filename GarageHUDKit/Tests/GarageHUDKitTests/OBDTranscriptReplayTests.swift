import XCTest
@testable import GarageHUDKit

/// Replays realistic ELM327 serial transcripts through the pure handshake + decoder — the
/// headless stand-in for hardware integration. These exercise the quirks real clones exhibit:
/// a version banner on ATZ, command echoes before ATE0 takes effect, "OK" acknowledgements,
/// "SEARCHING..." and "NO DATA" on PID polls, and error/timeout recovery. (Real-adapter,
/// ISO-TP/multi-ECU, and disconnect/reconnect transport tests still require a device — TD-004.)
final class OBDTranscriptReplayTests: XCTestCase {

    /// Drive the handshake from the opening command through a scripted list of completed
    /// replies, collecting the commands it asks to send. Stops at `.ready` or `.failed`.
    private func runHandshake(_ h0: ELM327Handshake, replies: [ELM327Handshake.Event]) -> (sent: [String], outcome: ELM327Handshake.Action) {
        var h = h0
        var sent: [String] = [h.openingCommand]   // the transport sends this first
        var last: ELM327Handshake.Action = .send(h.openingCommand)
        for event in replies {
            last = h.handle(event)
            switch last {
            case .send(let cmd): sent.append(cmd)
            case .ready, .failed: return (sent, last)
            }
        }
        return (sent, last)
    }

    func testHappyPathSessionReachesReadyInOrder() {
        // A clean clone: banner on ATZ, then OK for each config command.
        let transcript: [ELM327Handshake.Event] = [
            .reply("ELM327 v1.5"),   // ATZ
            .reply("ATE0\rOK"),      // ATE0 — echo still present until echo-off applies
            .reply("OK"),            // ATL0
            .reply("OK"),            // ATH0
            .reply("OK")             // ATSP0
        ]
        let result = runHandshake(ELM327Handshake(), replies: transcript)
        XCTAssertEqual(result.sent, ["ATZ", "ATE0", "ATL0", "ATH0", "ATSP0"])
        XCTAssertEqual(result.outcome, .ready)
    }

    func testGarbledResetRetriesThenRecovers() {
        // ATZ first answers with noise/error, then the real banner on retry.
        let transcript: [ELM327Handshake.Event] = [
            .reply("?"),             // ATZ → error, retry ATZ
            .reply("ELM327 v2.1"),   // ATZ → banner, proceed
            .reply("OK"), .reply("OK"), .reply("OK"), .reply("OK")
        ]
        let result = runHandshake(ELM327Handshake(), replies: transcript)
        XCTAssertEqual(result.sent, ["ATZ", "ATZ", "ATE0", "ATL0", "ATH0", "ATSP0"])
        XCTAssertEqual(result.outcome, .ready)
    }

    func testTimeoutMidConfigRetriesSameCommand() {
        let transcript: [ELM327Handshake.Event] = [
            .reply("ELM327 v1.5"),   // ATZ
            .timeout,                // ATE0 times out → retry ATE0
            .reply("OK"),            // ATE0 ok
            .reply("OK"), .reply("OK"), .reply("OK")
        ]
        let result = runHandshake(ELM327Handshake(), replies: transcript)
        XCTAssertEqual(result.sent, ["ATZ", "ATE0", "ATE0", "ATL0", "ATH0", "ATSP0"])
        XCTAssertEqual(result.outcome, .ready)
    }

    func testDeadAdapterFailsAfterRetryCap() {
        let transcript: [ELM327Handshake.Event] = [.timeout, .timeout, .timeout]  // ATZ never answers
        let result = runHandshake(ELM327Handshake(maxAttempts: 3), replies: transcript)
        XCTAssertEqual(result.outcome, .failed)
    }

    /// Once polling, the decoder must ignore the ELM327's non-data chatter and decode the real
    /// (headerless — ATH0 was sent) PID replies that follow.
    func testPollingTranscriptDecodesOnlyRealData() {
        let pollLines = [
            "SEARCHING...",          // first poll after ATSP0 — not data
            "41 0C 1A F8",           // RPM 1726
            "NO DATA",               // a PID this ECU doesn't support
            "41 05 5A",              // coolant 122°F
            "41 0D 64\r>"            // speed 100 km/h, with trailing prompt
        ]
        let readings = pollLines.compactMap { OBDPIDDecoder.decode($0) }
        XCTAssertEqual(readings.count, 3)                 // SEARCHING and NO DATA dropped
        XCTAssertEqual(readings.map(\.pid), [.engineRPM, .coolantTemp, .vehicleSpeed])
        XCTAssertEqual(readings[0].value, 1726, accuracy: 0.5)
    }
}
