import Foundation

/// A small, durable flight recorder for the latest physical adapter attempt. It contains only
/// GarageHUD connection stages, never raw vehicle replies, peripheral identifiers, or telemetry.
public struct OBDConnectionJournal: Codable, Equatable, Sendable {
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
