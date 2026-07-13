import Foundation

/// Single source of truth for the garage. Persists the whole vehicle graph locally as
/// JSON, then syncs that graph through CloudKit when enabled. Views only ever see
/// `@Published var vehicles` and `Binding<Vehicle>`, keeping persistence and sync
/// details out of the UI layer.
@MainActor
public final class GarageStore: ObservableObject {
    public static let maxGarageSlots = 4

    public enum SyncStatus: Equatable {
        case disabled
        case offline
        case syncing
        case synced
        /// A newer cloud version was found while this device was trying to push.
        /// The local attempted version was preserved as a conflict snapshot instead
        /// of silently overwriting the cloud record.
        case conflict(URL)
    }

    @Published public var vehicles: [Vehicle] = [] {
        didSet {
            save()
            // Don't push during load/seed or while applying a remote pull, and not until
            // the initial sync has decided direction — otherwise fresh seed data could
            // clobber newer cloud data before we've had a chance to pull it.
            if !isLoading && !isApplyingRemote && !initialSyncPending { schedulePush() }
        }
    }

    @Published public private(set) var syncStatus: SyncStatus = .disabled

    private let fileURL: URL
    private var isLoading = false

    // Sync state
    private let cloud: CloudSyncManager?
    private var isApplyingRemote = false
    private var initialSyncPending: Bool
    /// True when this launch loaded the bundled seed into an empty garage; lets initial sync
    /// prefer that fresh real data over an empty/stripped cloud record.
    private var didSeedThisLaunch = false
    private var pushTask: Task<Void, Never>?
    private let appliedKey = "GHUD.appliedCloudUpdatedAt"
    private var appliedCloudUpdatedAt: Date? {
        get { UserDefaults.standard.object(forKey: appliedKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: appliedKey) }
    }

    private var conflictSnapshotsDirectory: URL {
        let dir = fileURL.deletingLastPathComponent().appendingPathComponent("Conflict Snapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// `syncEnabled: false` (used by unit-ish/local runs) skips all CloudKit calls.
    public init(fileURL: URL? = nil, syncEnabled: Bool = true) {
        self.fileURL = fileURL ?? GarageStore.defaultFileURL
        self.cloud = syncEnabled ? CloudSyncManager() : nil
        self.initialSyncPending = syncEnabled
        isLoading = true
        load()
        isLoading = false
        // Seed when there's no *real* data yet — empty, or only stripped shells left behind by a
        // stale cloud record. Once the seed's parts/records are present, this won't fire again.
        let hasRealData = vehicles.contains { !$0.parts.isEmpty || !$0.performanceRecords.isEmpty }
        if !hasRealData {
            if seedFromBundle() {
                didSeedThisLaunch = true
            } else if vehicles.isEmpty {
                seedDefaults()
            }
        }
        if cloud != nil {
            Task { await initialSync() }
        }
    }

    // MARK: - CloudKit sync

    private func allPhotoFilenames(_ list: [Vehicle]) -> [String] {
        list.flatMap { v in
            v.photos.map(\.filename)
                + v.parts.flatMap { $0.photos.map(\.filename) }
                + v.buildEvents.flatMap { $0.photos.map(\.filename) }
        }
    }

    /// Called once at launch: pull cloud state (apply if newer), or seed the cloud from
    /// local if nothing's up there yet.
    private func initialSync() async {
        guard let cloud else { return }
        guard await cloud.accountAvailable() else {
            syncStatus = .offline
            initialSyncPending = false
            return
        }
        syncStatus = .syncing
        if let remote = await cloud.pull() {
            let remoteHasRealData = remote.vehicles.contains { !$0.parts.isEmpty || !$0.performanceRecords.isEmpty }
            if didSeedThisLaunch && !remoteHasRealData {
                // We just seeded real data locally and the cloud only holds an empty/stripped
                // record — make the seed authoritative instead of letting stale cloud clobber it.
                initialSyncPending = false
                let stamp = Date()
                if await cloud.push(vehicles: vehicles, updatedAt: stamp) {
                    appliedCloudUpdatedAt = stamp
                    await cloud.uploadPhotos(filenames: allPhotoFilenames(vehicles))
                }
            } else {
                if appliedCloudUpdatedAt == nil || remote.updatedAt > appliedCloudUpdatedAt! {
                    applyRemote(remote.vehicles)
                    appliedCloudUpdatedAt = remote.updatedAt
                    await cloud.downloadPhotos(filenames: allPhotoFilenames(remote.vehicles))
                    objectWillChange.send()
                }
                initialSyncPending = false
            }
        } else {
            // No cloud record yet — this device seeds the cloud.
            initialSyncPending = false
            await pushNow(vehicles)
        }
        syncStatus = .synced
    }

    /// Pull-only refresh, safe to call on foreground / manual "sync now".
    public func syncNow() {
        guard let cloud else { return }
        Task {
            guard await cloud.accountAvailable() else { syncStatus = .offline; return }
            syncStatus = .syncing
            if let remote = await cloud.pull(),
               appliedCloudUpdatedAt == nil || remote.updatedAt > appliedCloudUpdatedAt! {
                applyRemote(remote.vehicles)
                appliedCloudUpdatedAt = remote.updatedAt
                await cloud.downloadPhotos(filenames: allPhotoFilenames(remote.vehicles))
                objectWillChange.send()
            }
            syncStatus = .synced
        }
    }

    private func applyRemote(_ remote: [Vehicle]) {
        isApplyingRemote = true
        vehicles = remote
        isApplyingRemote = false
    }

    private func schedulePush() {
        guard cloud != nil else { return }
        pushTask?.cancel()
        let snapshot = vehicles
        pushTask = Task {
            try? await Task.sleep(nanoseconds: 900_000_000) // debounce rapid edits
            if Task.isCancelled { return }
            await pushNow(snapshot)
        }
    }

    private func pushNow(_ snapshot: [Vehicle]) async {
        guard let cloud else { return }
        guard await cloud.accountAvailable() else { syncStatus = .offline; return }
        syncStatus = .syncing

        // Conservative conflict guard: if another device has already pushed a newer
        // garage than the one this device last applied, do not overwrite it. Preserve
        // this device's attempted local state for manual recovery, then accept the
        // newer cloud state. This is still whole-document sync, but it prevents the
        // worst failure mode: silent cross-device data loss.
        if let remote = await cloud.pull(),
           let appliedCloudUpdatedAt,
           remote.updatedAt > appliedCloudUpdatedAt {
            let snapshotURL = writeConflictSnapshot(snapshot, remoteUpdatedAt: remote.updatedAt)
            applyRemote(remote.vehicles)
            self.appliedCloudUpdatedAt = remote.updatedAt
            await cloud.downloadPhotos(filenames: allPhotoFilenames(remote.vehicles))
            syncStatus = .conflict(snapshotURL)
            return
        }

        let stamp = Date()
        if await cloud.push(vehicles: snapshot, updatedAt: stamp) {
            appliedCloudUpdatedAt = stamp
            await cloud.uploadPhotos(filenames: allPhotoFilenames(snapshot))
            syncStatus = .synced
        } else {
            syncStatus = .offline
        }
    }

    @discardableResult
    private func writeConflictSnapshot(_ snapshot: [Vehicle], remoteUpdatedAt: Date) -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let timestamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let remoteStamp = ISO8601DateFormatter()
            .string(from: remoteUpdatedAt)
            .replacingOccurrences(of: ":", with: "-")
        let url = conflictSnapshotsDirectory
            .appendingPathComponent("garage-conflict-local-\(timestamp)-remote-\(remoteStamp).json")

        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: .atomic)
        }
        return url
    }

    /// On a fresh install, prefer a bundled `garage_seed.json` (the real build data
    /// baked into the app) over the generic 2-car placeholder. Also restores any
    /// bundled full-res photos into the image store so galleries work offline.
    @discardableResult
    private func seedFromBundle() -> Bool {
        guard let url = Bundle.main.url(forResource: "garage_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return false }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let seeded = try? decoder.decode([Vehicle].self, from: data), !seeded.isEmpty else { return false }

        for vehicle in seeded {
            let photos = vehicle.photos
                + vehicle.parts.flatMap(\.photos)
                + vehicle.buildEvents.flatMap(\.photos)
            for photo in photos where !ImageStore.exists(filename: photo.filename) {
                let base = (photo.filename as NSString).deletingPathExtension
                let ext = (photo.filename as NSString).pathExtension
                if let purl = Bundle.main.url(forResource: base, withExtension: ext),
                   let pdata = try? Data(contentsOf: purl) {
                    ImageStore.writeRaw(filename: photo.filename, data: pdata)
                }
            }
        }
        vehicles = seeded
        return true
    }

    public static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GarageHUD", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("garage.json")
    }

    /// Set when a present-but-corrupt garage file was found on load. The unreadable bytes are
    /// preserved at this URL rather than discarded, so nothing is lost silently.
    @Published public private(set) var loadFailureBackupURL: URL?

    public func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        switch GaragePersistence.decode(data) {
        case .empty:
            break
        case .ok(let loaded):
            vehicles = loaded
        case .migratedLegacy(let loaded):
            vehicles = loaded
            // Rewrite in the versioned format in place (guard bypassed — this is migration).
            if let migrated = try? GaragePersistence.encode(loaded) {
                try? migrated.write(to: fileURL, options: .atomic)
            }
        case .unreadable:
            // Never silently wipe. Preserve the unreadable file, then continue with an empty
            // garage (which will restore from iCloud or the seed rather than overwrite blindly).
            loadFailureBackupURL = backUpUnreadableFile(data)
            vehicles = []
        }
    }

    private func backUpUnreadableFile(_ data: Data) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = fileURL.deletingLastPathComponent().appendingPathComponent("garage-unreadable-\(stamp).json")
        try? data.write(to: url, options: .atomic)
        return url
    }

    public func save() {
        guard !isLoading else { return }
        guard let data = try? GaragePersistence.encode(vehicles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    public func addVehicle(_ vehicle: Vehicle) {
        vehicles.append(vehicle)
    }

    public func deleteVehicle(id: UUID) {
        if let vehicle = vehicles.first(where: { $0.id == id }) {
            for filename in allPhotoFilenames([vehicle]) {
                ImageStore.delete(filename: filename)
            }
        }
        vehicles.removeAll { $0.id == id }
    }

    /// Clean-slate build: no seeded vehicles. A fresh install shows an empty 4-bay garage
    /// ready for the user to add/import their own cars.
    private func seedDefaults() {
        vehicles = []
    }
}
