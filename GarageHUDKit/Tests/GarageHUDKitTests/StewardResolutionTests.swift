import XCTest
@testable import GarageHUDKit

/// A colored Steward note maps to concrete, tappable fixes. This verifies the pure mapping from an
/// observation to its resolution options (the dashboard just presents and performs them).
final class StewardResolutionTests: XCTestCase {
    private let car = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)

    private func obs(_ ruleID: String) -> StewardObservation {
        StewardObservation(ruleID: ruleID, statement: "s", evidence: "e",
                           confidence: .strong, tone: .caution, provenance: .derived)
    }

    func testMaintenanceOverdueOffersServiceAndSchedule() {
        let item = UUID()
        let opts = StewardResolution.options(for: obs("maintenance.overdue.\(item.uuidString)"), in: car)
        XCTAssertEqual(opts.map(\.action), [.markServiced(item), .editSchedule(item)])
    }

    func testServiceInServiceOffersBackInService() {
        XCTAssertEqual(StewardResolution.options(for: obs("service.inService"), in: car).map(\.action),
                       [.markBackInService])
    }

    func testComponentGapOffersConfirmStockOrAddPart() {
        let opts = StewardResolution.options(for: obs("gap.\(PartCategory.forcedInduction.rawValue)"), in: car)
        XCTAssertEqual(opts.map(\.action),
                       [.confirmStock(.forcedInduction), .addPart(.forcedInduction)])
    }

    func testPerformanceAndActivityAndLiveRoutes() {
        XCTAssertEqual(StewardResolution.options(for: obs("tune.stale"), in: car).map(\.action), [.logPerformance])
        XCTAssertEqual(StewardResolution.options(for: obs("build.quiet"), in: car).map(\.action), [.logActivity])
        XCTAssertEqual(StewardResolution.options(for: obs("data.undatedParts"), in: car).map(\.action), [.reviewParts])
        XCTAssertEqual(StewardResolution.options(for: obs("live.boostCeiling"), in: car).map(\.action), [.editEnvelope])
    }

    func testInformationalNoteHasNoOptionsAndIsNotActionable() {
        let quiet = obs("some.unknown.rule")
        XCTAssertTrue(StewardResolution.options(for: quiet, in: car).isEmpty)
        XCTAssertFalse(StewardResolution.isActionable(quiet, in: car))
    }
}
