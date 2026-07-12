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

/// The measured/estimated distinction must actually change what Steward claims.
final class LiveProvenanceTests: XCTestCase {
    private func vehicle() -> Vehicle { Vehicle(make: "T", model: "C", year: 2020, garageSlot: 1) }

    func testMeasuredRaisesProvenanceAndConfidence() {
        let hot = LiveMetrics(rpm: 6000, speedMph: 80, coolantTempF: 240, boostPsi: 12, throttlePercent: 100)
        let estimated = Steward.observe(live: hot, for: vehicle(), measured: false).first { $0.tone == .advisory }
        let measured = Steward.observe(live: hot, for: vehicle(), measured: true).first { $0.tone == .advisory }
        XCTAssertEqual(estimated?.provenance, .estimatedLive)
        XCTAssertEqual(measured?.provenance, .measuredLive)
        XCTAssertGreaterThan(measured?.confidence ?? 0, estimated?.confidence ?? 0)
    }
}
