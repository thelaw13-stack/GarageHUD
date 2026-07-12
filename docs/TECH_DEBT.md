# Technical Debt Register

## TD-004 — OBD adapter pairing & hardware validation

Priority: High

Current state: The BLE `OBDLiveDataSource` runs a response-driven `ELM327Handshake`, pairs
write+notify characteristics from the same service, and reconnects on drop. Decoding and the
handshake state machine are unit-tested.

Risk: Auto-connect trusts service-UUID discovery — there is no validated adapter *profile*, no
user device selection, and no ELM327 identity verification, so it could connect to the wrong
device/characteristic pair. The transport is also unproven against physical hardware.

Next steps: Add a persisted adapter profile (peripheral UUID, service/char UUIDs, write mode,
name, last-connected), require user selection during pairing, auto-reconnect only to a validated
device, and verify ELM327 identity on `ATZ`. Then add real-adapter integration, ISO-TP/multi-ECU,
disconnect/reconnect, and recorded serial-transcript replay tests. See ADR-0004.

## TD-005 — No schema versioning in persisted JSON

Priority: Medium

Current state: Migration relies on additive, default-valued fields; older `garage.json` decodes
into newer models. Decode uses `try?` and falls back to `[]` on failure — silent.

Risk: A non-additive schema change would fail silently and read an empty garage.

Next steps: Add a `schemaVersion`, a versioned decode/transform path, and a non-silent failure
mode. See [PERSISTENCE.md](PERSISTENCE.md). Until then, additive-only changes are mandatory.

## TD-006 — CI / strict concurrency — RESOLVED

Priority: Medium — done

Resolution: `.github/workflows/ci.yml` runs package `swift build`/`swift test` and an
iOS-simulator app build on every push/PR. The package compiles under
`-strict-concurrency=complete` with **zero** warnings; the two genuinely main-thread-confined
spots were annotated honestly (`OBDLiveDataSource` is `@unchecked Sendable` with a documented
confinement invariant + explicit `.main` CB queue; `ImageStore.thumbCache` is
`nonisolated(unsafe)` since `NSCache` is internally thread-safe).

Remaining: migrating to the Swift 6 language mode outright (vs. complete checking in 5.10) can
follow once the app target also builds clean; not blocking.

## TD-001 — Whole-document CloudKit sync

Priority: High

Current state: The entire garage graph is synced as one JSON blob.

Risk: Concurrent edits from multiple devices cannot be merged semantically. A conservative conflict guard now prevents silent overwrites, but true merging is deferred.

Near-term decision: Accept whole-document sync while preserving conflict snapshots.

Long-term direction: Move toward event-based records or operation-based sync once vehicle history grows.

## TD-002 — Test coverage expanding

Priority: Medium

Current state: 81 tests across model math, build-sheet parsing, cost/efficiency derivations, JSON
round-tripping, the full Steward ruleset (per-vehicle, fleet, live, briefing), evidence-band and
knowledge-state honesty (incl. incomplete-record false-positives), power basis, operating
envelopes, injected-clock determinism, OBD PID decoding, the ELM327 handshake state machine, and
the reusable stream lifecycle.

Risk: Everything requiring real hardware or the UI layer is uncovered — see TD-004 (real ELM327 /
ISO-TP / reconnect / transcript replay) and TD-006 (CI). SwiftUI navigation, accessibility, and
sync conflict-snapshot encoding also remain manual/on-device.

Next steps: Add the hardware-adjacent transport tests under TD-004 and the CI harness under TD-006;
add conflict-snapshot encoding tests alongside TD-001 work.

## TD-003 — Steward vocabulary exists conceptually, not in code

Priority: Medium

Current state: `BuildAdvisor` and `PurchaseManager` are early seeds of Steward-like behavior.

Risk: One-off managers could proliferate without a coherent Steward service boundary.

Next steps: Do not refactor prematurely. Watch for the third advisor-like service; that is likely the threshold for introducing a `Steward` namespace/boundary.
