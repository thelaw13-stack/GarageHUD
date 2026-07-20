import XCTest
@testable import GarageHUDKit

/// ADR-0006 — the pure foundation of the provenance spine.
///
/// The whole design rests on two properties: a strict ordering of origins, and a combine rule that
/// can only ever lose confidence. If either is wrong, a guess can launder itself into a fact.
final class ProvenanceTests: XCTestCase {

    func testOriginsAreOrderedWeakestToStrongest() {
        XCTAssertTrue(Provenance.unknown < .unspecified)
        XCTAssertTrue(Provenance.unspecified < .estimated)
        XCTAssertTrue(Provenance.estimated < .sourced)
        XCTAssertTrue(Provenance.sourced < .measured)
    }

    func testADerivationInheritsItsWeakestInput() {
        // The anti-laundering rule: a measured figure combined with an estimate is only an estimate.
        XCTAssertEqual(Provenance.weakest([.measured, .estimated]), .estimated)
        XCTAssertEqual(Provenance.weakest([.sourced, .measured]), .sourced)
        XCTAssertEqual(Provenance.weakest([.measured, .measured]), .measured)
    }

    func testAFigureDerivedFromNothingIsNotKnowledge() {
        XCTAssertEqual(Provenance.weakest([]), .unknown)
    }

    func testAnUnknownInputPoisonsTheDerivation() {
        // W-070's root: a baseline derived from an unrecorded value must not be presented at all.
        XCTAssertEqual(Provenance.weakest([.measured, .unknown]), .unknown)
        XCTAssertFalse(Provenance.unknown.canSeedDerivation)
        XCTAssertTrue(Provenance.estimated.canSeedDerivation)
    }

    func testOnlyAMeasurementMayReadAsMeasured() {
        XCTAssertTrue(Provenance.measured.canPresentAsMeasured)
        for p: Provenance in [.unknown, .unspecified, .estimated, .sourced] {
            XCTAssertFalse(p.canPresentAsMeasured, "\(p) must not present as measured")
        }
    }

    func testLegacyValuesAreNeverLabelledAsGuesses() {
        // The migration promise: an unmarked value from before provenance existed renders exactly as
        // today. It has estimate-strength for the monotonic rule but carries no origin label.
        XCTAssertNil(Provenance.unspecified.label)
        XCTAssertTrue(Provenance.unspecified < .estimated, "must not out-rank a real estimate")
        XCTAssertTrue(Provenance.unspecified.canSeedDerivation, "legacy data still works as before")
        // And it cannot masquerade as measured, so it can't launder either.
        XCTAssertFalse(Provenance.unspecified.canPresentAsMeasured)
    }

    func testTheOtherOriginsCarryAPlainLabel() {
        XCTAssertEqual(Provenance.unknown.label, "not recorded")
        XCTAssertEqual(Provenance.estimated.label, "estimate")
        XCTAssertEqual(Provenance.sourced.label, "documented")
        XCTAssertEqual(Provenance.measured.label, "measured")
    }

    func testProvenanceSurvivesACodableRoundTrip() {
        for p in Provenance.allCases {
            let data = try! JSONEncoder().encode(p)
            XCTAssertEqual(try! JSONDecoder().decode(Provenance.self, from: data), p)
        }
    }
}
