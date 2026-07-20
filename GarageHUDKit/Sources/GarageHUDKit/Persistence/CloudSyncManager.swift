import Foundation
import CloudKit
import Security

/// CloudKit-backed sync for the whole garage. Strategy: the entire vehicle graph is
/// stored as one JSON blob in a single "Garage" record (last-writer-wins by timestamp),
/// and each photo file is a separate "Photo" record so images transfer once and are
/// reused. This keeps the merge model dead simple for a single-user, few-device setup.
@MainActor
public final class CloudSyncManager {
    public static let containerID = "iCloud.com.vanlaw.GarageHUD"

    private let container: CKContainer
    private var db: CKDatabase { container.privateCloudDatabase }
    private let garageRecordID = CKRecord.ID(recordName: "garage-main")

    private let garageRecordType = "Garage"
    private let photoRecordType = "Photo"

    /// Whether this build actually carries the iCloud container entitlement — so an *unsigned*
    /// desktop build degrades to local-only instead of trapping inside `CKContainer`.
    ///
    /// The `SecTask` entitlement-inspection APIs are macOS-only (they aren't in the iOS SDK), and
    /// the check only exists for the unsigned-desktop case in the first place. On iOS the app is
    /// always provisioned with the container, so the answer is unconditionally yes.
    public static var canUseCloudKitContainer: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.icloud-container-identifiers" as CFString,
                nil
              ) else { return false }
        if let containers = value as? [String] { return containers.contains(containerID) }
        if let container = value as? String { return container == containerID }
        return false
        #else
        return true
        #endif
    }

    public init() {
        container = CKContainer(identifier: Self.containerID)
    }

    public enum SyncError: Error { case noAccount }

    // MARK: Change notification (W-068)

    /// Identifier for the standing subscription. Fixed, so re-running this is idempotent — saving a
    /// subscription that already exists returns `.serverRejectedRequest`, which is a success here,
    /// not a failure. Without a fixed id every launch would create another subscription and the
    /// owner's iCloud would slowly fill with duplicates all pushing for the same change.
    private static let garageSubscriptionID = "garage-changes-v1"

    /// Ask iCloud to nudge this device whenever the garage record changes on another one.
    ///
    /// Before this, GarageHUD only fetched at launch and on becoming active, so an app left open —
    /// a Mac sitting frontmost in the garage — never learned the phone had written anything, and
    /// correct sync looked broken. The nudge is silent: `shouldSendContentAvailable` wakes the app
    /// to fetch, with no alert, no badge, no sound, and no permission prompt. It carries no data
    /// itself; it only says "look again", and the existing guarded pull decides everything else.
    ///
    /// Safe to call on every launch. Failure is deliberately quiet — an owner with no iCloud
    /// account, or offline, still has a working local app, and this is an optimisation of freshness
    /// rather than a requirement for correctness.
    public func ensureChangeSubscription() async {
        guard Self.canUseCloudKitContainer, await accountAvailable() else { return }
        let subscription = CKQuerySubscription(
            recordType: garageRecordType,
            predicate: NSPredicate(value: true),
            subscriptionID: Self.garageSubscriptionID,
            options: [.firesOnRecordUpdate, .firesOnRecordCreation])
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true   // silent: wake and fetch, never alert the owner
        subscription.notificationInfo = info
        do {
            _ = try await db.save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already registered from a previous launch — the desired state, not a problem.
        } catch {
            // Offline, no account, or iCloud unavailable. Launch/foreground fetching still works.
        }
    }

    public func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    // MARK: Payload envelope

    /// The versioned cloud payload — the same `{ schemaVersion, vehicles }` envelope as the local
    /// file, so a schema version now travels with the synced graph (this is what makes a future
    /// non-additive change to the cloud model safe). Pure and CloudKit-free, so it's unit-testable.
    nonisolated static func encodePayload(_ vehicles: [Vehicle]) throws -> Data {
        try GaragePersistence.encode(vehicles)
    }

    /// Decodes a cloud payload, tolerating BOTH the versioned document and a pre-versioning bare
    /// `[Vehicle]` array (records written by older builds), so introducing the envelope never drops
    /// an existing device's cloud data. Nil when the payload is empty or unreadable.
    nonisolated static func decodePayload(_ data: Data) -> [Vehicle]? {
        switch GaragePersistence.decode(data) {
        case .ok(let vehicles), .migratedLegacy(let vehicles): return vehicles
        case .empty, .unsupportedVersion, .unreadable: return nil
        }
    }

    // MARK: Pull

    public struct RemoteGarage {
        public let vehicles: [Vehicle]
        public let updatedAt: Date
    }

    public enum PullResult {
        case found(RemoteGarage)
        case notFound
        case unreadable
        case failed

        /// Only an explicit CloudKit `unknownItem` is authority to create the singleton record.
        /// A transport or decode failure must never masquerade as an empty cloud garage.
        var permitsInitialSeed: Bool {
            if case .notFound = self { return true }
            return false
        }
    }

    /// Fetches the cloud garage without collapsing absence, unreadable data, and transport failure
    /// into one value. Only `.notFound` permits the caller to seed a new singleton record.
    public func pull() async -> PullResult {
        do {
            let record = try await db.record(for: garageRecordID)
            guard let updatedAt = record["updatedAt"] as? Date,
                  let asset = record["payload"] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url),
                  let vehicles = Self.decodePayload(data) else { return .unreadable }
            return .found(RemoteGarage(vehicles: vehicles, updatedAt: updatedAt))
        } catch let error as CKError where error.code == .unknownItem {
            return .notFound
        } catch {
            return .failed
        }
    }

    // MARK: Push

    /// Writes the garage JSON to the cloud with the given timestamp. Fetch-then-modify so
    /// we don't clobber the server change tag; on a conflict we still win (LWW by design).
    @discardableResult
    public func push(vehicles: [Vehicle], updatedAt: Date) async -> Bool {
        guard let data = try? Self.encodePayload(vehicles) else { return false }

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        guard (try? data.write(to: tmp)) != nil else { return false }
        defer { try? FileManager.default.removeItem(at: tmp) }

        let record: CKRecord
        if let existing = try? await db.record(for: garageRecordID) {
            record = existing
        } else {
            record = CKRecord(recordType: garageRecordType, recordID: garageRecordID)
        }
        record["payload"] = CKAsset(fileURL: tmp)
        record["updatedAt"] = updatedAt as NSDate

        do {
            _ = try await db.save(record)
            return true
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Someone else wrote concurrently — overwrite with the server's record object
            // carrying our newer payload (LWW).
            if let server = error.serverRecord {
                server["payload"] = CKAsset(fileURL: tmp)
                server["updatedAt"] = updatedAt as NSDate
                do {
                    _ = try await db.save(server)
                    return true
                } catch {
                    return false
                }
            }
            return false
        } catch {
            return false
        }
    }

    /// Deletes the garage record and all photo records from the cloud (full reset).
    public func wipeAll() async {
        _ = try? await db.deleteRecord(withID: garageRecordID)
        let query = CKQuery(recordType: photoRecordType, predicate: NSPredicate(value: true))
        if let result = try? await db.records(matching: query) {
            for (recordID, _) in result.matchResults {
                _ = try? await db.deleteRecord(withID: recordID)
            }
        }
    }

    // MARK: Photos

    private func photoRecordID(_ filename: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "photo-" + filename)
    }

    /// Uploads any local photo files not yet in the cloud. Best-effort; failures are skipped.
    public func uploadPhotos(filenames: [String]) async {
        for filename in filenames {
            let recID = photoRecordID(filename)
            if (try? await db.record(for: recID)) != nil { continue } // already uploaded
            let localURL = ImageStore.imagesDirectory.appendingPathComponent(filename)
            guard FileManager.default.fileExists(atPath: localURL.path) else { continue }
            let record = CKRecord(recordType: photoRecordType, recordID: recID)
            record["image"] = CKAsset(fileURL: localURL)
            record["filename"] = filename as NSString
            _ = try? await db.save(record)
        }
    }

    /// Downloads any referenced photos missing from the local image store.
    public func downloadPhotos(filenames: [String]) async {
        for filename in filenames where !ImageStore.exists(filename: filename) {
            guard let record = try? await db.record(for: photoRecordID(filename)),
                  let asset = record["image"] as? CKAsset,
                  let url = asset.fileURL,
                  let data = try? Data(contentsOf: url) else { continue }
            ImageStore.writeRaw(filename: filename, data: data)
        }
    }
}
