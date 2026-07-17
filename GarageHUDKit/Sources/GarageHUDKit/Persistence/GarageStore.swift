import Foundation

/// Single source of truth for the garage. Persists the whole vehicle graph locally as
/// JSON, then syncs that graph through CloudKit when enabled. Views only ever see
/// `@Published var vehicles` and `Binding<Vehicle>`, keeping persistence and sync
/// details out of the UI layer.
@MainActor
public final class GarageStore: ObservableObject {
    public static let maxGarageSlots = 8

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
    /// What changed since the last time the app was opened — the "since you were last here" digest,
    /// computed once at launch. Nil on a first launch or when nothing meaningful changed.
    @Published public private(set) var fleetDigest: FleetDigest?
    private let fleetSnapshotKey = "GHUD.fleetSnapshot.v1"

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
        let canSync = syncEnabled && CloudSyncManager.canUseCloudKitContainer
        self.cloud = canSync ? CloudSyncManager() : nil
        self.initialSyncPending = canSync
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
        // Keep valid 1...8 bay assignments visible, while repairing duplicates or truly
        // out-of-range slots so no vehicle is stranded beyond the garage.
        if normalizeGarageSlots() { changed = true }
        // Heal any duplicate record ids from past imports/merges — a duplicate id can hard-crash a
        // ForEach and confuse sheet(item:)/sync.
        for i in vehicles.indices where vehicles[i].dedupeRecordIDs() { changed = true }
        seededThisLaunch = changed
        if changed { save() }   // persist the seeded/normalized/healed garage
        rollFleetDigest()       // "since you were last here": diff prior snapshot, then re-baseline
        if cloud != nil {
            Task { await initialSync() }
        }
    }

    /// Preserve valid bay assignments in the visible 1...8 range. Repair duplicates or
    /// out-of-range slots into the first open bay so every vehicle stays reachable.
    @discardableResult
    private func normalizeGarageSlots() -> Bool {
        let order = vehicles
            .sorted { lhs, rhs in
                if lhs.garageSlot == rhs.garageSlot { return lhs.displayName < rhs.displayName }
                return lhs.garageSlot < rhs.garageSlot
            }
            .map(\.id)
        var occupied = Set<Int>()
        var changed = false
        for id in order {
            guard let idx = vehicles.firstIndex(where: { $0.id == id }) else { continue }
            let slot = vehicles[idx].garageSlot
            if (1...Self.maxGarageSlots).contains(slot), !occupied.contains(slot) {
                occupied.insert(slot)
                continue
            }
            if let repaired = (1...Self.maxGarageSlots).first(where: { !occupied.contains($0) }) {
                vehicles[idx].garageSlot = repaired
                occupied.insert(repaired)
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
        return (1...Self.maxGarageSlots).first { !used.contains($0) }
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

        // Conservative conflict guard: never overwrite cloud state this device hasn't seen.
        // That means (a) another device pushed a newer garage than the one we last applied, OR
        // (b) this device has never successfully applied ANY cloud state (`appliedCloudUpdatedAt`
        // is nil — e.g. the launch-time account check failed) yet a real cloud garage exists.
        // The old guard skipped case (b), so a fresh device with one local edit could silently
        // clobber the whole cloud garage it had just fetched. Preserve this device's attempted
        // local state for manual recovery, then accept the cloud state. The one exception is a
        // stripped/empty remote against a real local build (`shouldPreferLocal`) — there, local
        // is authoritative, as everywhere else.
        if let remote = await cloud.pull(),
           !shouldPreferLocal(over: remote.vehicles),
           appliedCloudUpdatedAt.map({ remote.updatedAt > $0 }) ?? true {
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

    /// Compute the "since you were last here" digest against the stored snapshot, then re-baseline
    /// the snapshot to the current fleet — so next launch measures from now. First launch (no prior
    /// snapshot) simply records the baseline and shows nothing.
    private func rollFleetDigest() {
        let previous: FleetSnapshot? = UserDefaults.standard.data(forKey: fleetSnapshotKey)
            .flatMap { try? JSONDecoder().decode(FleetSnapshot.self, from: $0) }
        fleetDigest = FleetDigestBuilder.digest(from: previous, to: vehicles)
        let current = FleetDigestBuilder.snapshot(of: vehicles)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: fleetSnapshotKey)
        }
    }

    /// Dismiss the digest (the owner tapped it away); it won't reappear until something changes.
    public func dismissFleetDigest() { fleetDigest = nil }

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

        var part = vehicles[si].parts.remove(at: pi)
        // The move is the *destination* car's install moment. Carrying the source car's install
        // date over would fabricate the new car's history — a turbo "installed 2021" on a car it
        // only reached today reads as years of undocumented boost to the sequence/stale-tune rules.
        if part.status == .installed { part.installDate = Date() }
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
