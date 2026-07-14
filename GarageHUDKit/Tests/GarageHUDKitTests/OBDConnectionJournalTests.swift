import XCTest
@testable import GarageHUDKit

final class OBDConnectionJournalTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let suite = "OBDConnectionJournalTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    func testBeginStartsANewDurableAttemptForTheSelectedHardware() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        OBDConnectionJournalStore.begin(selection: .otherBLE, defaults: defaults)
        OBDConnectionJournalStore.append(stage: "SCANNING", message: "Opening Bluetooth", defaults: defaults)

        let journal = OBDConnectionJournalStore.load(defaults: defaults)
        XCTAssertEqual(journal?.adapterSelection, .otherBLE)
        XCTAssertEqual(journal?.entries.map(\.stage), ["SCANNING"])
    }

    func testNewAttemptReplacesOldAttemptInsteadOfMixingSessions() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        OBDConnectionJournalStore.begin(selection: .obdLinkCX, defaults: defaults)
        OBDConnectionJournalStore.append(stage: "DEGRADED", message: "Old failure", defaults: defaults)
        OBDConnectionJournalStore.begin(selection: .otherBLE, defaults: defaults)

        let journal = OBDConnectionJournalStore.load(defaults: defaults)
        XCTAssertEqual(journal?.adapterSelection, .otherBLE)
        XCTAssertTrue(journal?.entries.isEmpty == true)
    }

    func testMeasuredStageProvesTheAttemptReachedDecodedData() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        OBDConnectionJournalStore.begin(selection: .obdLinkCX, defaults: defaults)
        OBDConnectionJournalStore.append(stage: "POLLING", message: "Waiting", defaults: defaults)
        XCTAssertFalse(OBDConnectionJournalStore.load(defaults: defaults)!.reachedMeasuredData)

        OBDConnectionJournalStore.append(stage: "MEASURING", message: "First PID", defaults: defaults)
        XCTAssertTrue(OBDConnectionJournalStore.load(defaults: defaults)!.reachedMeasuredData)
    }

    func testJournalIsBoundedForLongReconnectLoops() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        OBDConnectionJournalStore.begin(selection: .obdLinkCX, defaults: defaults)
        for index in 0..<50 {
            OBDConnectionJournalStore.append(stage: "RETRYING", message: "Attempt \(index)", defaults: defaults)
        }

        let entries = OBDConnectionJournalStore.load(defaults: defaults)!.entries
        XCTAssertEqual(entries.count, 32)
        XCTAssertEqual(entries.first?.message, "Attempt 18")
        XCTAssertEqual(entries.last?.message, "Attempt 49")
    }
}
