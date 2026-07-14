import Foundation

/// A small, durable flight recorder for the latest physical adapter attempt. It contains only
/// GarageHUD connection stages, never raw vehicle replies, peripheral identifiers, or telemetry.
public struct OBDConnectionJournal: Codable, Equatable, Sendable {
    public struct Diagnosis: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var nextAction: String
        public var isSuccessful: Bool

        public init(title: String, detail: String, nextAction: String, isSuccessful: Bool) {
            self.title = title
            self.detail = detail
            self.nextAction = nextAction
            self.isSuccessful = isSuccessful
        }
    }

    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var occurredAt: Date
        public var stage: String
        public var message: String

        public init(id: UUID = UUID(), occurredAt: Date = .now, stage: String, message: String) {
            self.id = id
            self.occurredAt = occurredAt
            self.stage = stage
            self.message = message
        }
    }

    public var startedAt: Date
    public var adapterSelection: OBDAdapterSelection
    public var entries: [Entry]

    public init(startedAt: Date = .now, adapterSelection: OBDAdapterSelection,
                entries: [Entry] = []) {
        self.startedAt = startedAt
        self.adapterSelection = adapterSelection
        self.entries = entries
    }

    public var latest: Entry? { entries.last }
    public var reachedMeasuredData: Bool { entries.contains { $0.stage == "MEASURING" } }

    public var diagnosis: Diagnosis {
        if reachedMeasuredData {
            return Diagnosis(
                title: "Measured data reached",
                detail: "GarageHUD opened the adapter and decoded live vehicle data.",
                nextAction: "This adapter is validated and ready for future sessions.",
                isSuccessful: true)
        }
        if !reached("FOUND") {
            return Diagnosis(
                title: "Adapter was not discovered",
                detail: "The iPhone scan did not see a compatible Bluetooth LE advertisement.",
                nextAction: "Verify the exact adapter model, turn the ignition on, and connect inside GarageHUD rather than Bluetooth Settings.",
                isSuccessful: false)
        }
        if !reached("SERVICES") {
            return Diagnosis(
                title: "Bluetooth link did not open",
                detail: "GarageHUD saw the adapter, but iOS never completed the BLE connection.",
                nextAction: "Close every other OBD app, power-cycle the adapter, and retry beside the vehicle.",
                isSuccessful: false)
        }
        if !reached("CHANNELS") {
            return Diagnosis(
                title: "Adapter services did not open",
                detail: "The BLE link opened, but its serial services or characteristics were not readable.",
                nextAction: "Retry with Other BLE selected, then share this report if the channel still is not found.",
                isSuccessful: false)
        }
        if !reached("WAKE-UP") {
            return Diagnosis(
                title: "No usable serial channel",
                detail: "GarageHUD inspected the adapter services but could not subscribe to a writable response channel.",
                nextAction: "Share this report so the adapter's service and characteristic layout can be added.",
                isSuccessful: false)
        }
        if !reached("READY") {
            return Diagnosis(
                title: "OBD processor did not answer",
                detail: "Bluetooth and the serial channel worked, but the adapter did not complete the ELM327 command handshake.",
                nextAction: "Start the engine, close other OBD apps, power-cycle the adapter, and retry.",
                isSuccessful: false)
        }
        return Diagnosis(
            title: "Vehicle data did not answer",
            detail: "The adapter passed its handshake, but no supported live PID was decoded.",
            nextAction: "Confirm the engine is running and share this report so the vehicle protocol can be checked.",
            isSuccessful: false)
    }

    public var supportReport: String {
        let result = diagnosis
        let formatter = ISO8601DateFormatter()
        var lines = [
            "GarageHUD OBD-II Connection Report",
            "Started: \(formatter.string(from: startedAt))",
            "Selected adapter: \(adapterSelection.displayName)",
            "Result: \(result.title)",
            "Assessment: \(result.detail)",
            "Next action: \(result.nextAction)",
            "",
            "Connection timeline:"
        ]
        lines += entries.map { entry in
            let elapsed = max(0, entry.occurredAt.timeIntervalSince(startedAt))
            return String(format: "+%.1fs  %@  %@", elapsed, entry.stage, entry.message)
        }
        return lines.joined(separator: "\n")
    }

    private func reached(_ stage: String) -> Bool {
        entries.contains { $0.stage == stage }
    }
}

public enum OBDConnectionJournalStore {
    private static let key = "GarageHUD.latestOBDConnectionJournal.v1"
    private static let entryLimit = 32

    public static func begin(selection: OBDAdapterSelection, defaults: UserDefaults = .standard) {
        save(OBDConnectionJournal(adapterSelection: selection), defaults: defaults)
    }

    public static func append(stage: String, message: String, defaults: UserDefaults = .standard) {
        var journal = load(defaults: defaults)
            ?? OBDConnectionJournal(adapterSelection: OBDAdapterSelectionStore.load(defaults: defaults))
        journal.entries.append(OBDConnectionJournal.Entry(stage: stage, message: message))
        journal.entries = Array(journal.entries.suffix(entryLimit))
        save(journal, defaults: defaults)
    }

    public static func load(defaults: UserDefaults = .standard) -> OBDConnectionJournal? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OBDConnectionJournal.self, from: data)
    }

    private static func save(_ journal: OBDConnectionJournal, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(journal) else { return }
        defaults.set(data, forKey: key)
    }
}
