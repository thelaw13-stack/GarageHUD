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

    func testManifoldPressureDecodesRawKPa() {
        // 010B reply "41 0B 96" → 0x96 = 150 kPa absolute. The decoder reports raw MAP; gauge
        // boost is computed against *measured* baro (or sea level until baro answers).
        let r = OBDPIDDecoder.decode("41 0B 96")
        XCTAssertEqual(r?.pid, .intakeManifoldPressure)
        XCTAssertEqual(r?.value ?? 0, 150, accuracy: 0.001)
        XCTAssertEqual(OBDPIDDecoder.gaugeBoostPsi(mapKPa: 150, baroKPa: OBDPIDDecoder.seaLevelKPa),
                       (150 - 101.325) * 0.145038, accuracy: 0.001)
    }

    func testBarometricPressureDecodesKPa() {
        // 0133 reply "41 33 63" → 0x63 = 99 kPa ambient.
        let r = OBDPIDDecoder.decode("41 33 63")
        XCTAssertEqual(r?.pid, .barometricPressure)
        XCTAssertEqual(r?.value ?? 0, 99, accuracy: 0.001)
    }

    func testGaugeBoostUsesMeasuredBaroNotSeaLevel() {
        // Denver: baro ~83 kPa. 10 psi of real boost is MAP ≈ 152 kPa. Against measured baro the
        // gauge figure is right; against the old hardcoded sea-level constant it read ~2.7 psi low.
        let mapKPa = 83.0 + 10.0 / 0.145038
        XCTAssertEqual(OBDPIDDecoder.gaugeBoostPsi(mapKPa: mapKPa, baroKPa: 83), 10, accuracy: 0.01)
        XCTAssertLessThan(OBDPIDDecoder.gaugeBoostPsi(mapKPa: mapKPa, baroKPa: OBDPIDDecoder.seaLevelKPa), 7.4)
    }

    func testVacuumReadsNegativeBoost() {
        // 30 kPa manifold vacuum → negative gauge psi, physically correct off-throttle
        let r = OBDPIDDecoder.decode("410B1E") // 0x1E = 30
        XCTAssertEqual(r?.value ?? 0, 30, accuracy: 0.001)
        XCTAssertLessThan(OBDPIDDecoder.gaugeBoostPsi(mapKPa: r?.value ?? 0,
                                                      baroKPa: OBDPIDDecoder.seaLevelKPa), 0)
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
        XCTAssertEqual(h.handle(.reply("OK")), .send("0100"))   // the protocol bind (W-052)
        XCTAssertEqual(h.handle(.reply("SEARCHING...\r41 00 BE 3E B8 11")), .ready)
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
        XCTAssertEqual(h.handle(.reply("OK")), .send("0100"))  // then it answers -> bind
        XCTAssertEqual(h.handle(.reply("41 00 BE 3E B8 11")), .ready)
    }

    func testSuccessfulReplyResetsAttemptCounter() {
        var h = ELM327Handshake(configCommands: ["ATE0", "ATSP0"], maxAttempts: 2)
        _ = h.handle(.reply("ELM327"))                         // → ATE0
        XCTAssertEqual(h.handle(.timeout), .send("ATE0"))      // 1 miss on ATE0
        XCTAssertEqual(h.handle(.reply("OK")), .send("ATSP0")) // recovers, counter resets
        XCTAssertEqual(h.handle(.timeout), .send("ATSP0"))     // 1 miss on ATSP0 (not 2)
    }

    /// Identity verification: a device that answers ATZ cleanly but isn't an ELM327 is rejected
    /// outright — the guard against pairing to the wrong adapter.
    func testRejectsNonELM327Device() {
        var h = ELM327Handshake()
        XCTAssertEqual(h.handle(.reply("OBDII v1.0")), .failed)
    }

    func testIdentityCheckCanBeDisabled() {
        var h = ELM327Handshake(configCommands: [], verifyIdentity: false)
        XCTAssertEqual(h.handle(.reply("WHATEVER")), .send("0100"))   // still binds the vehicle
        XCTAssertEqual(h.handle(.reply("4100BE3EB811")), .ready)
    }
}

final class OBDAdapterProfileTests: XCTestCase {
    func testProfileCodableRoundTrip() throws {
        let p = OBDAdapterProfile(
            peripheralID: UUID(), name: "OBDLink LX", serviceUUID: "FFF0",
            writeCharUUID: "FFF2", notifyCharUUID: "FFF1",
            writeWithoutResponse: true, lastConnected: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(OBDAdapterProfile.self, from: data)
        XCTAssertEqual(p, back)
    }
}
