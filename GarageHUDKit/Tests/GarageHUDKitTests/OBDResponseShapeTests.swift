import XCTest
@testable import GarageHUDKit

/// W-069 — can the connection report tell a multi-ECU vehicle from a single-ECU one?
///
/// Before this, it could not: a Tundra session on 2026-07-20 came back indistinguishable from a
/// single-responder car, so the multi-ECU criterion was *unmeasured* rather than passed or failed,
/// and a scarce driveway session was spent finding that out.
final class OBDResponseShapeTests: XCTestCase {

    func testASingleResponderIsNotNoteworthy() {
        let shape = OBDResponseShape.analyze("41 0C 1A F8")
        XCTAssertEqual(shape.dataLineCount, 1)
        XCTAssertFalse(shape.isMultiResponder)
        XCTAssertFalse(shape.isSegmented)
        XCTAssertFalse(shape.isNoteworthy, "the ordinary case must not clutter the report")
    }

    func testSeveralControlUnitsAnsweringOneRequestIsDetected() {
        // Two ECUs answering the same PID — exactly what a truck is expected to do, and what the
        // decoder throws away by keeping only the first decodable line.
        let shape = OBDResponseShape.analyze("41 0C 1A F8\r41 0C 1B 04")
        XCTAssertEqual(shape.dataLineCount, 2)
        XCTAssertTrue(shape.isMultiResponder)
        XCTAssertTrue(shape.isNoteworthy)
    }

    func testAMultiFrameTransferIsDetected() {
        // The ELM's segmented form with headers off: "0:", "1:", "2:" …
        let shape = OBDResponseShape.analyze("0: 41 00 BE 3F\r1: A8 13 00 00\r2: 00 00 00 00")
        XCTAssertTrue(shape.isSegmented)
        XCTAssertTrue(shape.isNoteworthy)
    }

    func testSegmentLinesAreNotMiscountedAsSeparateResponders() {
        // The failure that would quietly ruin the measurement: counting continuation frames as
        // independent ECUs would report multi-responder on every long single-ECU reply, and the
        // report would be confidently wrong rather than silent.
        let shape = OBDResponseShape.analyze("0: 41 00 BE 3F\r1: 41 00 A8 13")
        XCTAssertTrue(shape.isSegmented)
        XCTAssertFalse(shape.isMultiResponder, "continuation frames are one responder, not several")
    }

    func testStatusMarkersAndNoiseAreIgnored() {
        // "SEARCHING..." arriving in the same chunk as real data cost a whole driveway session once
        // (W-052). It must not be counted as a responder either.
        let shape = OBDResponseShape.analyze("SEARCHING...\r41 0C 1A F8")
        XCTAssertEqual(shape.dataLineCount, 1)
        XCTAssertFalse(shape.isMultiResponder)

        XCTAssertEqual(OBDResponseShape.analyze("NO DATA").dataLineCount, 0)
        XCTAssertFalse(OBDResponseShape.analyze("").isNoteworthy)
        XCTAssertFalse(OBDResponseShape.analyze("STOPPED").isNoteworthy)
    }

    func testTheReportLineSaysWhatWasSeen() {
        XCTAssertEqual(OBDResponseShape.analyze("41 0C 1A F8\r41 0C 1B 04").journalMessage,
                       "2 control units answered the same request")
        XCTAssertTrue(OBDResponseShape.analyze("0: 41 00 BE 3F\r1: A8 13 00 00")
                        .journalMessage.contains("multi-frame"))
    }

    func testAnalysisIsPurelyObservational() {
        // The point of the design: this reads bytes the proven handshake already receives. If a
        // future change makes it require a probe command, this test is the reminder of why not —
        // the bring-up is proven across three field sessions.
        let chunk = "41 0C 1A F8\r41 0C 1B 04"
        XCTAssertEqual(OBDResponseShape.analyze(chunk), OBDResponseShape.analyze(chunk))
    }
}
