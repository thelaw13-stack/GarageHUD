import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// A block of text shared as an actual named file.
///
/// Sharing a bare `String` via `ShareLink` gives the share sheet no filename and no file
/// representation, so "Save to Files" has nothing to write and falls back to stale transfer-buffer
/// data (whatever was last copied). This exports a titled `.txt` for file-shaped destinations
/// (Save to Files, Mail attachments) *and* the plain text for text destinations (Copy, Messages),
/// so every share target behaves.
public struct SharableTextFile: Transferable, Sendable {
    public let fileName: String   // without extension, e.g. "S2000 build sheet"
    public let text: String

    public init(fileName: String, text: String) {
        let safe = fileName.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.fileName = safe.isEmpty ? "GarageHUD" : safe
        self.text = text
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
            .suggestedFileName { "\($0.fileName).txt" }
        ProxyRepresentation(exporting: \.text)
    }
}
