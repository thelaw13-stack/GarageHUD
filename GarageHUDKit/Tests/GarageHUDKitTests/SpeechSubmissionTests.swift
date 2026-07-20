import XCTest
@testable import GarageHUDKit

/// W-062 — field-found 2026-07-19: the mic listened and transcribed correctly, but tapping it a
/// second time stopped without sending, so asking one question took two gestures. Tim's standing
/// rule is one gesture, one response. The submit rule is pinned here; the interaction itself is
/// device-validated, since it needs a real microphone.
final class SpeechSubmissionTests: XCTestCase {

    func testASpokenQuestionIsSubmitted() {
        XCTAssertEqual(SpeechSubmission.utteranceToSubmit("what should I watch"), "what should I watch")
    }

    func testSurroundingWhitespaceIsTrimmed() {
        XCTAssertEqual(SpeechSubmission.utteranceToSubmit("  how much power?\n"), "how much power?")
    }

    func testSayingNothingCancelsRatherThanAskingAnEmptyQuestion() {
        // Tapping the mic and saying nothing is a cancel. Submitting "" would fire an exchange with
        // no question in it.
        XCTAssertNil(SpeechSubmission.utteranceToSubmit(""))
        XCTAssertNil(SpeechSubmission.utteranceToSubmit("   "))
        XCTAssertNil(SpeechSubmission.utteranceToSubmit("\n\t "))
    }

    func testInternalPunctuationAndSpacingSurvive() {
        // Only the edges are trimmed — the recognizer's own phrasing reaches the Steward intact.
        XCTAssertEqual(SpeechSubmission.utteranceToSubmit(" will my fueling keep up, at 20 psi? "),
                       "will my fueling keep up, at 20 psi?")
    }
}
