import SwiftUI
import UniformTypeIdentifiers

/// The whole garage as an exportable `.json` backup file — shared via the system share sheet so
/// the owner can save a copy to Files, iCloud Drive, email, etc. Data safety after the
/// whole-document-sync scares: a real, portable backup of a carefully-entered fleet.
public struct GarageBackup: Transferable {
    public let data: Data
    public let filename: String

    public init(data: Data, filename: String) {
        self.data = data
        self.filename = filename
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

public extension GarageBackup {
    /// A dated backup of the given garage store.
    @MainActor static func of(_ store: GarageStore) -> GarageBackup {
        let stamp = ISO8601DateFormatter().string(from: Date()).prefix(10)   // yyyy-MM-dd
        return GarageBackup(data: store.exportData(), filename: "GarageHUD-backup-\(stamp).json")
    }
}
