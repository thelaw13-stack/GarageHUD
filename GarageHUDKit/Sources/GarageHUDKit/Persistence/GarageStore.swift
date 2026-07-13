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
        // Apply the bundled seed exactly once per install: fill a bare matching vehicle in
        // place, and add any seed vehicle that isn't present into a free bay. Gated by a flag so
        // an intentionally-emptied garage isn't re-seeded later.
        var changed = false
        if !UserDefaults.standard.bool(forKey: seedAppliedKey) {
            if applyInitialSeed() { changed = true }
            UserDefaults.standard.set(true, forKey: seedAppliedKey)
        }
        // Pack vehicles into contiguous low bays so none is ever stranded in a hidden slot
        // beyond the visible range (which happened when a stray vehicle occupied a bay).
        if normalizeGarageSlots() { changed = true }
        // Heal any duplicate record ids from past imports/merges — a duplicate id can hard-crash a
        // ForEach and confuse sheet(item:)/sync.
        for i in vehicles.indices where vehicles[i].dedupeRecordIDs() { changed = true }
        seededThisLaunch = changed
        if changed { save() }   // persist the seeded/normalized/healed garage
        if cloud != nil {
            Task { await initialSync() }
        }
    }

    /// Reassign garage slots to 1…N (ordered by current slot) so every vehicle sits in a visible
    /// bay. Returns true if anything moved.
    @discardableResult
    private func normalizeGarageSlots() -> Bool {
        let order = vehicles.sorted { $0.garageSlot < $1.garageSlot }.map(\.id)
        var changed = false
        for (i, id) in order.enumerated() {
            if let idx = vehicles.firstIndex(where: { $0.id == id }), vehicles[idx].garageSlot != i + 1 {
                vehicles[idx].garageSlot = i + 1
                changed = true
            }
        }
        return changed
    }

    private let seedAppliedKey = "GHUD.didApplyInitialSeed.v5"
    /// True when this launch merged/added seed data — so the local (now-superset) garage is
    /// pushed authoritatively rather than risk a smaller cloud record overwriting the addition.
    private var seededThisLaunch = false

    /// One-time seed: merge into bare matches, then add any missing seed vehicles into free bays.
    /// Returns true if it changed anything.
    @discardableResult
    private func applyInitialSeed() -> Bool {
        guard let seeds = loadSeedVehicles() else { return false }
        var changed = mergeSeedIntoBareMatches()
        for seed in seeds where !vehicles.contains(where: { $0.identityMatches(seed) }) {
            guard let slot = firstFreeSlot() else { break }
            var v = seed
            v.garageSlot = slot
            vehicles.append(v)
            changed = true
        }
        return changed
    }

    private func firstFreeSlot() -> Int? {
        let used = Set(vehicles.map(\.garageSlot))
        return (1...8).first { !used.contains($0) }
    }

    /// Fills any *bare* existing vehicle (no parts logged) with a matching seed vehicle's build —
    /// parts, records, events, notes, service status, and any missing specs — preserving the
    /// existing vehicle's id and garage slot. Runs once: once parts are present it no longer
    /// matches. Returns true if anything was merged.
    @discardableResult
    private func mergeSeedIntoBareMatches() -> Bool {
        guard let seeds = loadSeedVehicles() else { return false }
        var merged = false
        for i in vehicles.indices where vehicles[i].parts.isEmpty {
            guard let seed = seeds.first(where: { $0.identityMatches(vehicles[i]) }) else { continue }
            vehicles[i] = vehicles[i].filledFromSeed(seed)
            merged = true
        }
        return merged
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
            if seededThisLaunch || shouldPreferLocal(over: remote.vehicles) {
                // We just added seed data (a superset), or local holds a real build the cloud
                // lacks — make local authoritative rather than let the cloud overwrite it.
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

    /// A pull must never replace a real local build with an empty/stripped cloud record. Guards
    /// both initial sync and manual refresh against the whole-doc-sync data-loss path.
    private func shouldPreferLocal(over remote: [Vehicle]) -> Bool {
        func real(_ list: [Vehicle]) -> Bool { list.contains { !$0.parts.isEmpty || !$0.performanceRecords.isEmpty } }
        return real(vehicles) && !real(remote)
    }

    /// Pull-only refresh, safe to call on foreground / manual "sync now".
    public func syncNow() {
        guard let cloud else { return }
        Task {
            guard await cloud.accountAvailable() else { syncStatus = .offline; return }
            syncStatus = .syncing
            if let remote = await cloud.pull(),
               !shouldPreferLocal(over: remote.vehicles),
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
        guard let seeded = loadSeedVehicles() else { return false }
        vehicles = seeded
        return true
    }

    /// Decodes the bundled `garage_seed.json` and restores any bundled full-res photos into the
    /// image store. Returns nil if there's no seed. Shared by the empty-garage seed and the
    /// bare-vehicle merge.
    private func loadSeedVehicles() -> [Vehicle]? {
        guard let url = Bundle.main.url(forResource: "garage_seed", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let seeded = try? decoder.decode([Vehicle].self, from: data), !seeded.isEmpty else { return nil }

        for vehicle in seeded {
            let photos = vehicle.photos + vehicle.parts.flatMap(\.photos) + vehicle.buildEvents.flatMap(\.photos)
            for photo in photos where !ImageStore.exists(filename: photo.filename) {
                let base = (photo.filename as NSString).deletingPathExtension
                let ext = (photo.filename as NSString).pathExtension
                if let purl = Bundle.main.url(forResource: base, withExtension: ext),
                   let pdata = try? Data(contentsOf: purl) {
                    ImageStore.writeRaw(filename: photo.filename, data: pdata)
                }
            }
        }
        return seeded
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

    /// The whole garage as a versioned JSON backup the owner can export and keep.
    public func exportData() -> Data {
        (try? GaragePersistence.encode(vehicles)) ?? Data("[]".utf8)
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

    /// Move a part from one vehicle to another — a real fleet workflow (e.g. pulling an amp out of
    /// one build and installing it in another). The part keeps its identity and history-linkable id,
    /// and a dated build event is logged on both cars so the transfer shows up in each timeline.
    /// Returns true if the part was found on the source and moved.
    @discardableResult
    public func moveParts(partID: UUID, from sourceID: UUID, to destID: UUID) -> Bool {
        guard sourceID != destID,
              let si = vehicles.firstIndex(where: { $0.id == sourceID }),
              let di = vehicles.firstIndex(where: { $0.id == destID }),
              let pi = vehicles[si].parts.firstIndex(where: { $0.id == partID })
        else { return false }

        let part = vehicles[si].parts.remove(at: pi)
        vehicles[di].parts.append(part)

        let sourceName = vehicles[si].displayName
        let destName = vehicles[di].displayName
        vehicles[si].buildEvents.append(BuildEvent(
            title: "Removed: \(part.name)",
            eventDescription: "Moved to \(destName).",
            relatedPartIDs: [part.id]))
        vehicles[di].buildEvents.append(BuildEvent(
            title: "Installed: \(part.name)",
            eventDescription: "Moved from \(sourceName).",
            relatedPartIDs: [part.id]))
        save()
        return true
    }

    /// Clean-slate build: no seeded vehicles. A fresh install shows an empty 4-bay garage
    /// ready for the user to add/import their own cars.
    private func seedDefaults() {
        vehicles = []
    }
}
