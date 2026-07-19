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

    func testConsecutiveDuplicateTransitionsAreCollapsedWithoutHidingLaterRetries() {
        let (defaults, suite) = defaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        OBDConnectionJournalStore.begin(selection: .veepeakOBDCheckBLE, defaults: defaults)
        for _ in 0..<4 {
            OBDConnectionJournalStore.append(
                stage: "PROTOCOL",
                message: "Negotiating the vehicle protocol…",
                defaults: defaults)
        }

        var entries = OBDConnectionJournalStore.load(defaults: defaults)!.entries
        XCTAssertEqual(entries.count, 1)

        OBDConnectionJournalStore.append(stage: "RETRYING", message: "Bluetooth link dropped", defaults: defaults)
        OBDConnectionJournalStore.append(
            stage: "PROTOCOL",
            message: "Negotiating the vehicle protocol…",
            defaults: defaults)

        entries = OBDConnectionJournalStore.load(defaults: defaults)!.entries
        XCTAssertEqual(entries.map(\.stage), ["PROTOCOL", "RETRYING", "PROTOCOL"])
    }

    func testDiagnosisIdentifiesDiscoveryAndChannelFailures() {
        let notSeen = OBDConnectionJournal(adapterSelection: .otherBLE, entries: [
            .init(stage: "SCANNING", message: "Searching")
        ])
        XCTAssertEqual(notSeen.diagnosis.title, "Adapter was not discovered")

        let noChannel = OBDConnectionJournal(adapterSelection: .otherBLE, entries: [
            .init(stage: "FOUND", message: "Saw adapter"),
            .init(stage: "SERVICES", message: "Bluetooth linked"),
            .init(stage: "CHANNELS", message: "Inspecting characteristics")
        ])
        XCTAssertEqual(noChannel.diagnosis.title, "No usable serial channel")
        XCTAssertTrue(noChannel.diagnosis.nextAction.contains("Share this report"))
    }

    func testDiagnosisSeparatesHandshakeFromVehicleDataFailures() {
        let handshake = OBDConnectionJournal(adapterSelection: .veepeakOBDCheckBLE, entries: [
            .init(stage: "FOUND", message: "Saw adapter"),
            .init(stage: "SERVICES", message: "Found FFF0"),
            .init(stage: "CHANNELS", message: "Found FFF1 and FFF2"),
            .init(stage: "WAKE-UP", message: "Sent ATZ")
        ])
        XCTAssertEqual(handshake.diagnosis.title, "OBD processor did not answer")

        var vehicle = handshake
        vehicle.entries.append(.init(stage: "READY", message: "Handshake complete"))
        vehicle.entries.append(.init(stage: "POLLING", message: "Waiting for PID"))
        XCTAssertEqual(vehicle.diagnosis.title, "Vehicle data did not answer")
    }

    func testVeepeakFieldRegression_ELMAnsweredButVehicleBindFailed() {
        let journal = OBDConnectionJournal(adapterSelection: .veepeakOBDCheckBLE, entries: [
            .init(stage: "FOUND", message: "Saw VEEPEAK at signal -38 dBm"),
            .init(stage: "SERVICES", message: "Adapter exposed 1 service: FFF0"),
            .init(stage: "CHANNELS", message: "Using service FFF0, receive FFF1, write FFF2"),
            .init(stage: "WAKE-UP", message: "Bluetooth paired. Waking the OBD command processor"),
            .init(stage: "BINDING", message: "ELM configured; requesting supported vehicle PIDs"),
            .init(stage: "BIND-REPLY", message: "ELM reported no vehicle data"),
            .init(stage: "BIND-FAILED", message: "No supported 41 00 vehicle response was confirmed")
        ])

        XCTAssertEqual(journal.diagnosis.title, "Vehicle protocol was not confirmed")
        XCTAssertTrue(journal.diagnosis.detail.contains("ELM command processor answered"))
        XCTAssertFalse(journal.supportReport.contains("adapter is fine"))
        XCTAssertFalse(journal.supportReport.contains("OBD processor did not answer"))
    }

    func testBoundedJournalKeepsFurthestMilestoneTruthWhenEarlyEntriesAreEvicted() {
        let journal = OBDConnectionJournal(adapterSelection: .veepeakOBDCheckBLE, entries: [
            .init(stage: "BINDING", message: "ELM configured"),
            .init(stage: "BIND-FAILED", message: "No 41 00 response"),
            .init(stage: "RETRYING", message: "Reconnect")
        ])
        XCTAssertEqual(journal.diagnosis.title, "Vehicle protocol was not confirmed")
    }

    func testSupportReportIsShareableAndContainsNoPeripheralIdentifier() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let journal = OBDConnectionJournal(startedAt: start, adapterSelection: .vgateICarProBLE, entries: [
            .init(occurredAt: start.addingTimeInterval(1.25), stage: "FOUND", message: "Saw Vgate")
        ])

        XCTAssertTrue(journal.supportReport.contains("GarageHUD OBD-II Connection Report"))
        XCTAssertTrue(journal.supportReport.contains("Selected adapter: Vgate iCar Pro BLE"))
        XCTAssertTrue(journal.supportReport.contains("+1.2s  FOUND  Saw Vgate"))
        XCTAssertFalse(journal.supportReport.contains("peripheralID"))
    }
}
