import XCTest
@testable import GarageHUDKit

/// The decoder is the honest core of measured telemetry — SAE J1979 math on the ECU's
/// actual bytes. These pin the standard formulas against known responses, including the
/// ELM327 quirks (spaces, prompt, echoes, non-data replies).
final class OBDPIDDecoderTests: XCTestCase {

    func testRPMFormula() {
        // 010C reply "41 0C 1A F8" → ((0x1A*256)+0xF8)/4 = (6656+248)/4 = 1726 rpm
        let r = OBDPIDDecoder.decode("41 0C 1A F8")
        XCTAssertEqual(r?.pid, .engineRPM)
        XCTAssertEqual(r?.value ?? 0, 1726, accuracy: 0.001)
    }

    func testSpeedConvertsKmhToMph() {
        // 010D reply "41 0D 64" → 100 km/h → 62.1371 mph
        let r = OBDPIDDecoder.decode("41 0D 64")
        XCTAssertEqual(r?.pid, .vehicleSpeed)
        XCTAssertEqual(r?.value ?? 0, 62.1371, accuracy: 0.001)
    }

    func testCoolantConvertsCToF() {
        // 0105 reply "41 05 5A" → 0x5A=90, 90-40=50°C → 122°F
        let r = OBDPIDDecoder.decode("41 05 5A")
        XCTAssertEqual(r?.pid, .coolantTemp)
        XCTAssertEqual(r?.value ?? 0, 122, accuracy: 0.001)
    }

    func testThrottlePercent() {
        // 0111 reply "41 11 FF" → 255*100/255 = 100%
        XCTAssertEqual(OBDPIDDecoder.decode("41 11 FF")?.value ?? 0, 100, accuracy: 0.001)
    }

    func testBoostFromManifoldPressure() {
        // 010B reply "41 0B 96" → 0x96=150 kPa → (150-101.325)*0.145038 ≈ 7.06 psi gauge
        let r = OBDPIDDecoder.decode("41 0B 96")
        XCTAssertEqual(r?.pid, .intakeManifoldPressure)
        XCTAssertEqual(r?.value ?? 0, (150 - 101.325) * 0.145038, accuracy: 0.001)
    }

    func testVacuumReadsNegativeBoost() {
        // 30 kPa manifold vacuum → negative gauge psi, physically correct off-throttle
        let r = OBDPIDDecoder.decode("410B1E") // 0x1E = 30
        XCTAssertLessThan(r?.value ?? 0, 0)
    }

    func testTolerantOfNoSpacesAndPrompt() {
        XCTAssertEqual(OBDPIDDecoder.decode("410C1AF8\r>")?.value ?? 0, 1726, accuracy: 0.001)
    }

    func testNonDataRepliesReturnNil() {
        XCTAssertNil(OBDPIDDecoder.decode("NO DATA"))
        XCTAssertNil(OBDPIDDecoder.decode("SEARCHING..."))
        XCTAssertNil(OBDPIDDecoder.decode(">"))
        XCTAssertNil(OBDPIDDecoder.decode(""))
    }

    func testUnknownPIDReturnsNil() {
        // 0146 (ambient air temp) — valid frame, but not a PID we read
        XCTAssertNil(OBDPIDDecoder.decode("41 46 3C"))
    }
}

/// The honesty guarantee: "measured" reflects the *value's* own source and freshness, never
/// the transport. A stale or missing value yields no observation; an adapter value yields a
/// measured one only while it's fresh.
final class LiveProvenanceTests: XCTestCase {
    private func vehicle() -> Vehicle { Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1) }

    private func frame(coolant: Double, source: MeasurementSource, age: TimeInterval) -> LiveTelemetryFrame {
        LiveTelemetryFrame(
            coolantTempF: TimedMeasurement(coolant, source: source, at: Date().addingTimeInterval(-age)),
            connectionState: .polling)
    }

    func testMeasuredValueRaisesProvenanceAndConfidence() {
        let est = Steward.observe(frame: frame(coolant: 240, source: .simulated, age: 0), for: vehicle()).first { $0.tone == .advisory }
        let meas = Steward.observe(frame: frame(coolant: 240, source: .obdAdapter, age: 0), for: vehicle()).first { $0.tone == .advisory }
        XCTAssertEqual(est?.provenance, .estimatedLive)
        XCTAssertEqual(meas?.provenance, .measuredLive)
        XCTAssertGreaterThan(meas?.confidence ?? .insufficient, est?.confidence ?? .insufficient)
    }

    func testStaleValueProducesNoObservation() {
        // A hot coolant reading that's older than the freshness window must not be reported.
        let stale = frame(coolant: 240, source: .obdAdapter, age: LiveFreshness.window + 1)
        XCTAssertTrue(Steward.observe(frame: stale, for: vehicle()).isEmpty)
    }

    func testMissingMetricProducesNoObservation() {
        // Default/absent values never fabricate an observation.
        let empty = LiveTelemetryFrame(connectionState: .polling)
        XCTAssertTrue(Steward.observe(frame: empty, for: vehicle()).isEmpty)
    }

    func testFreshnessBoundary() {
        let m = TimedMeasurement(100.0, source: .obdAdapter, at: Date().addingTimeInterval(-(LiveFreshness.window - 0.1)))
        XCTAssertTrue(m.isFresh(within: LiveFreshness.window))
        let old = TimedMeasurement(100.0, source: .obdAdapter, at: Date().addingTimeInterval(-(LiveFreshness.window + 0.1)))
        XCTAssertFalse(old.isFresh(within: LiveFreshness.window))
    }
}

/// The ELM327 bring-up must be a real command-response sequence: one command at a time,
/// advancing only on a valid reply, retrying on error/timeout, and failing after the cap.
final class ELM327HandshakeTests: XCTestCase {

    func testHappyPathWalksResetThenConfigThenReady() {
        var h = ELM327Handshake(configCommands: ["ATE0", "ATSP0"])
        XCTAssertEqual(h.openingCommand, "ATZ")
        XCTAssertEqual(h.handle(.reply("ELM327 v1.5")), .send("ATE0"))
        XCTAssertEqual(h.handle(.reply("OK")), .send("ATSP0"))
        XCTAssertEqual(h.handle(.reply("OK")), .ready)
    }

    func testErrorRepliesRetryThenFailAtCap() {
        var h = ELM327Handshake(configCommands: ["ATE0"], maxAttempts: 3)
        _ = h.handle(.reply("ELM327 v1.5"))          // now on ATE0
        XCTAssertEqual(h.handle(.reply("?")), .send("ATE0"))   // attempt 1 → retry
        XCTAssertEqual(h.handle(.reply("?")), .send("ATE0"))   // attempt 2 → retry
        XCTAssertEqual(h.handle(.reply("?")), .failed)         // attempt 3 → give up
    }

    func testTimeoutRetriesThenSucceeds() {
        var h = ELM327Handshake(configCommands: ["ATE0"])
        _ = h.handle(.reply("ELM327 v1.5"))
        XCTAssertEqual(h.handle(.timeout), .send("ATE0"))      // retry the same command
        XCTAssertEqual(h.handle(.reply("OK")), .ready)         // then it answers
    }

    func testSuccessfulReplyResetsAttemptCounter() {
        var h = ELM327Handshake(configCommands: ["ATE0", "ATSP0"], maxAttempts: 2)
        _ = h.handle(.reply("ELM327"))                         // → ATE0
        XCTAssertEqual(h.handle(.timeout), .send("ATE0"))      // 1 miss on ATE0
        XCTAssertEqual(h.handle(.reply("OK")), .send("ATSP0")) // recovers, counter resets
        XCTAssertEqual(h.handle(.timeout), .send("ATSP0"))     // 1 miss on ATSP0 (not 2)
    }
}
