# Persistence & Migration

## Storage model

GarageHUD's model layer is plain `Codable` structs (`Vehicle`, `Part`, `PerformanceRecord`,
`Note`, `BuildEvent`, `Photo`, …), **not** SwiftData. SwiftData's `@Model` macro required a full
Xcode toolchain that wasn't available when the model layer was built; `Codable` + an
`ObservableObject` store proved simpler and fully portable, and there's been no reason to switch.

Two stores:

- **`GarageStore`** — the source of truth. Encodes `[Vehicle]` to JSON at
  `~/Library/Application Support/GarageHUD/garage.json` (ISO-8601 dates). Views bind into
  `GarageStore.vehicles`; all persistence and sync sit behind it.
- **`ImageStore`** — full-resolution photos as files under `…/GarageHUD/Photos/`, referenced by
  filename from `Photo` values (so the JSON graph stays small).

## Sync

The whole vehicle graph is synced as one JSON payload on a single private CloudKit record;
photos are separate `Photo` records. Last-writer-wins, with a **conservative conflict guard**:
before pushing, the store checks whether CloudKit holds a newer version than this device last
applied, and if so it does **not** overwrite — it writes the attempted local snapshot into
`Conflict Snapshots/` and applies the newer cloud graph. The rule is *visible conflict over
invisible data loss*. Rationale and future direction:
[ADR-0001](adr/ADR-0001-whole-document-sync.md).

## Migration strategy

There is **no explicit schema version** in the JSON today. The working strategy is
**additive, default-valued fields**:

- New fields are tolerated on decode. **Important:** Swift's *synthesized* `Decodable` does
  NOT apply a property's default value for a missing key — it throws `keyNotFound`. So models
  that gain fields (`Vehicle`, `Part`, `ServiceStatus`, `OperatingEnvelope`) implement a custom
  `init(from:)` using `decodeIfPresent(...) ?? default`. That is what actually lets an older
  `garage.json` (and the bundled seed) decode cleanly. Relying on property defaults alone is a
  latent data-loss bug — it silently failed the seed once (see `SeedDecodeCheck`).

### Rules for changing the schema

1. **Only add** fields, and give them a default or make them optional. Safe, no migration.
2. **Never rename or retype** a field in place — that is a breaking change to existing JSON.
3. **Never remove** a field another device might still be writing until all devices have shipped
   the removal.

### Schema versioning (TD-005 — resolved)

The local file is a versioned `GaragePersistence.Document { schemaVersion, vehicles }` (see
`GaragePersistence.swift`). Loading is typed, not `try? … ?? []`:

- **current/forward** — a versioned document decodes to `.ok`; a *newer* `schemaVersion` still
  decodes its vehicles (fields are additive), so a newer device's file isn't dropped;
- **legacy** — a pre-versioning bare `[Vehicle]` array decodes to `.migratedLegacy` and is
  rewritten in the versioned format in place;
- **corrupt** — a present-but-unreadable file is `.unreadable`: it is copied to
  `garage-unreadable-<timestamp>.json` and surfaced via `GarageStore.loadFailureBackupURL`
  rather than silently discarded. The app then continues empty (restoring from iCloud or seed)
  instead of overwriting the bad file blindly.

The **CloudKit** payload is now the *same* versioned `Document { schemaVersion, vehicles }` envelope
as the local file (`CloudSyncManager.encodePayload` / `decodePayload`, reusing `GaragePersistence`).
A schema version therefore travels with the synced graph, so a future non-additive change to the
cloud model is safe. The pull tolerates **both** the versioned document and a pre-versioning bare
`[Vehicle]` array, so records written by older builds are still read, never dropped. Covered by
`CloudPayloadTests`.

One-time transition caveat: a bare-array-only (not-yet-updated) device cannot read the new versioned
payload. This is inherent to changing the envelope; on a single-user, few-device setup where devices
ship together it's a non-issue. The reverse direction is safe — updated devices read old records.
