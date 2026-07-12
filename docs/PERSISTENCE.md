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

- New fields are added as `Optional` or with a default value (e.g. `factoryPowerBasis` defaults
  to `.factoryCrank`; `confirmedStockSystems` defaults to `[]`; `operatingEnvelopeOverride` is
  optional). Because Swift's synthesized `Codable` treats a missing key with a default/optional
  as absent-but-fine, **older `garage.json` files decode cleanly** into newer models. This is
  how the round-2 review changes (power basis, knowledge confirmations, operating envelopes)
  shipped without a migration step.

### Rules for changing the schema

1. **Only add** fields, and give them a default or make them optional. Safe, no migration.
2. **Never rename or retype** a field in place — that is a breaking change to existing JSON.
3. **Never remove** a field another device might still be writing until all devices have shipped
   the removal.

### Known gap (tracked in TECH_DEBT)

Decoding uses `try? decoder.decode([Vehicle].self, …)`, which returns `nil` on **any** decode
failure. Combined with additive-only changes this is safe in practice, but it means a genuinely
breaking change would fail **silently** rather than surfacing — the app would read an empty
garage instead of erroring. Before any non-additive schema change, this needs:

- a `schemaVersion` field in the persisted payload,
- a versioned decode path (decode-old → transform → current), and
- a non-silent failure mode (surface a load error / preserve the unreadable file) rather than
  discarding to `[]`.

Until that exists, treat rule 1 above as mandatory, not merely preferred.
