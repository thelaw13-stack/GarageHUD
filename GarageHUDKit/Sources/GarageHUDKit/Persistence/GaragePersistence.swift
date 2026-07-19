import Foundation

/// Local-file serialization for the garage, versioned so the schema can evolve without silent
/// data loss. Pure and static so every path (current, legacy, corrupt) is unit-tested without
/// touching disk or CloudKit.
///
/// The on-disk format is a `Document { schemaVersion, vehicles }`. A pre-versioning file (a bare
/// `[Vehicle]` array) is recognized and migrated. A file that is present but decodes as neither
/// is reported `unreadable` — never silently discarded — so the caller can preserve it.
public enum GaragePersistence {
    public static let currentSchemaVersion = 1

    struct Document: Codable {
        var schemaVersion: Int
        var vehicles: [Vehicle]
    }

    public enum LoadResult: Equatable {
        case empty                          // no/blank file — a fresh garage
        case ok([Vehicle])                  // decoded at the current (or a newer) version
        case migratedLegacy([Vehicle])      // decoded a pre-versioning bare array
        case unsupportedVersion(Int)         // newer schema: preserve; never downgrade/rewrite
        case unreadable                     // present but corrupt — must be preserved, not dropped
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ vehicles: [Vehicle]) throws -> Data {
        try encoder().encode(Document(schemaVersion: currentSchemaVersion, vehicles: vehicles))
    }

    public static func decode(_ data: Data) -> LoadResult {
        guard !data.isEmpty else { return .empty }
        let dec = decoder()
        // Current: a versioned document. A future schema is recognized but not decoded into this
        // older mutable model, because saving it would discard fields this app does not know.
        if let doc = try? dec.decode(Document.self, from: data) {
            guard doc.schemaVersion <= currentSchemaVersion else {
                return .unsupportedVersion(doc.schemaVersion)
            }
            return .ok(doc.vehicles)
        }
        // Legacy: a pre-versioning bare array.
        if let legacy = try? dec.decode([Vehicle].self, from: data) {
            return .migratedLegacy(legacy)
        }
        return .unreadable
    }
}
