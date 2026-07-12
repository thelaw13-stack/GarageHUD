import Foundation

/// One dated moment in a vehicle's life, projected from whichever record produced it.
/// The timeline is the *spine* of the build: parts don't just exist, they were installed
/// on a date, in an order — and that order is what lets the Steward reason about sequence
/// ("boost went on before the fueling caught up"), not just present state.
public struct TimelineEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case partInstalled(PartCategory)
        case partRemoved(PartCategory)
        case performance(PerformanceType)
        case buildEvent
        case note
    }

    public let id: UUID
    public let date: Date
    public let title: String
    public let detail: String
    public let kind: Kind
    /// The originating record's id (part, record, event, or note) so the UI can route a tap
    /// back to the right editor.
    public let sourceID: UUID
}

public extension Vehicle {
    /// The unified history spine — every *dated* record merged newest-first. Records without
    /// a date (e.g. a wishlist part, or an installed part whose install date was never entered)
    /// are intentionally absent: the spine only carries moments we can actually place in time.
    var timeline: [TimelineEntry] {
        var entries: [TimelineEntry] = []

        for part in parts {
            if let installed = part.installDate {
                entries.append(TimelineEntry(
                    id: UUID(), date: installed,
                    title: "Installed \(part.name)",
                    detail: part.category.rawValue,
                    kind: .partInstalled(part.category), sourceID: part.id))
            }
            if let removed = part.removeDate {
                entries.append(TimelineEntry(
                    id: UUID(), date: removed,
                    title: "Removed \(part.name)",
                    detail: part.category.rawValue,
                    kind: .partRemoved(part.category), sourceID: part.id))
            }
        }

        for record in performanceRecords {
            entries.append(TimelineEntry(
                id: UUID(), date: record.date,
                title: record.type.rawValue,
                detail: record.summary,
                kind: .performance(record.type), sourceID: record.id))
        }

        for event in buildEvents {
            entries.append(TimelineEntry(
                id: UUID(), date: event.date,
                title: event.title,
                detail: event.eventDescription,
                kind: .buildEvent, sourceID: event.id))
        }

        for note in notes {
            entries.append(TimelineEntry(
                id: UUID(), date: note.date,
                title: note.title,
                detail: note.body,
                kind: .note, sourceID: note.id))
        }

        return entries.sorted { $0.date > $1.date }
    }

    /// The earliest dated installed part in a category, if its install date is on record.
    /// Used by the Steward to judge *ordering* between subsystems.
    func earliestInstall(in category: PartCategory) -> Date? {
        parts
            .filter { $0.category == category && $0.status != .removed }
            .compactMap { $0.installDate }
            .min()
    }
}
