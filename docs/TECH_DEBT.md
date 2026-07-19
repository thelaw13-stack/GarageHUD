# Technical Debt Register

## TD-007 — Voice + conversational Steward: on-device validation

Priority: Medium

Done: TTS now selects the best installed voice (Premium > Enhanced > default) instead of the
robotic compact default — ranking is pure and unit-tested (`StewardVoicePreference`). "Ask
Steward" gained an on-device LLM path via Apple's Foundation Models (`StewardLLM` /
`StewardAssistant`), grounded strictly in the car's record (`StewardGrounding`, tested) with
honesty instructions, gated three ways (`canImport` / iOS 26 / runtime availability) and falling
back to the keyword `StewardConversation` core (tested). The grounding record and voice ranking
are covered; the assistant's "always answers" contract is tested.

Voice quality resolved via **cloud neural TTS** (`CloudVoice` — OpenAI `gpt-4o-mini-tts`), since
on-device `AVSpeechSynthesizer` caps at robotic (Apple reserves the Siri voice). Owner supplies a
key (Keychain-stored via `KeychainStore`), toggles it in `VoiceSettingsView`; the session speaks
cloud audio and falls back to the best on-device voice when disabled/offline/on error. Request
building, config persistence, keychain round-trip, and the active/fallback gate are tested.

Remaining (needs real hardware/OS): (1) exercise the cloud voice end-to-end on device with a real
key — latency, audio-session interplay with the mic, and cost in practice; the on-device Premium
path is still the offline fallback (the first-run nudge when only a default voice is installed —
`needsBetterVoiceDownload` — is surfaced as a dismissible banner in Ask Steward; W-010, `e72a4b0`).

Owner decision (2026-07-19): cloud voice stays **off** — GarageHUD is to remain free to run for now,
so the paid `gpt-4o-mini-tts` path will not be exercised. The on-device Premium/Enhanced voice is
therefore the shipping voice path, not a fallback. Item (1) below is deferred by choice, not blocked
by capability. (2) Exercise the LLM path on an Apple-Intelligence device (iPhone
15 Pro+ / iOS 26): latency, refusal behavior on out-of-record questions, and that it honors the
confidence bands in practice. (3) Speech-in (`SFSpeechRecognizer`) is still unexercised against a
real microphone — shared with the note in README "Status & known gaps."

## TD-004 — OBD adapter pairing & hardware validation

Priority: High → partially addressed

Done: `ELM327Handshake` verifies ELM327 identity on the `ATZ` banner (rejects non-ELM devices);
`OBDLiveDataSource` pairs write+notify from the *same* service, connects only to a known
peripheral when `knownPeripheralID` is set, and assembles a persistable `OBDAdapterProfile`
(peripheral UUID, service/char UUIDs, write mode, name, last-connected) on successful bring-up.
Identity verification and the profile model are unit-tested.

Pairing UI, owner selection, profile persistence, and known-peripheral reconnect are implemented.
The July 19 Veepeak field sequence now proves real BLE advertisement discovery, the FFF0/FFF1/FFF2
serial channel, notification subscription, ELM identity, command configuration, a supported `41 00`
vehicle response, polling, and decoded measured data. Two independent sessions reached measured data
in 2.4 and 2.7 seconds, so the success is repeatable rather than a single lucky bind. A genuine
mid-session disconnect/reconnect and a multi-ECU/ISO-TP vehicle remain unverified on hardware.
Synthetic transcript replay is done (`OBDTranscriptReplayTests`), and the connection report cleanly
separates ELM/configuration success from a vehicle-bind failure with privacy-safe outcome categories.

## TD-005 — Schema versioning in persisted JSON — RESOLVED

Priority: Medium — done

Resolution: The local file is a versioned `GaragePersistence.Document { schemaVersion, vehicles }`
with a typed load result (`.ok` / `.migratedLegacy` / `.unsupportedVersion` / `.unreadable` /
`.empty`). Legacy bare
arrays migrate in place; a corrupt file is backed up to `garage-unreadable-<ts>.json` and
surfaced via `GarageStore.loadFailureBackupURL` instead of being silently discarded. Covered by
`GaragePersistenceVersioningTests`. See [PERSISTENCE.md](PERSISTENCE.md).

Resolved (2026-07-16): the CloudKit payload now uses the same versioned
`Document { schemaVersion, vehicles }` envelope (`CloudSyncManager.encodePayload` / `decodePayload`
reusing `GaragePersistence`). The pull still accepts a legacy bare array so older records aren't
dropped; `CloudPayloadTests` covers the round-trip, legacy tolerance, and unreadable→nil. See the
one-time transition caveat in [PERSISTENCE.md](PERSISTENCE.md).

Resolved (2026-07-19): newly written conflict and pre-restore recovery snapshots also use the same
versioned document. Discovery and restore continue accepting legacy bare-array snapshots, while new
safety copies preserve an explicit schema boundary. `RecoverySnapshotTests` pins both behaviors.

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

## TD-001 — Whole-document CloudKit sync — PROMOTED (top of the board)

Priority: **Top** — promoted 2026-07-18 on Fable's re-review: live telemetry going real multiplied
the concurrent-write exposure the same day it validated the adapter picker. The phone now writes
pull reports *during* driveway sessions while the Mac holds spec edits — exactly the pattern
last-writer-wins punishes.

Current state: The entire garage graph is synced as one JSON blob. The conservative conflict guard
(snapshots, never-applied-state protection, Recovery UI) prevents silent whole-document loss; the
**W-054 bridge** preserves append-only records (pull reports, performance records, build events,
notes, photos) across document adoption — a driveway pull survives a Mac push; and **tombstones
(W-056, phase 1)** now close the deletion half: `Vehicle.deletedRecordIDs` is a synced set every
append-record deletion writes to, and `GarageMerge` unions both sides' tombstones and suppresses
any id they name, so a delete on either device propagates instead of being resurrected by the
other's held copy. Delete-wins is deliberate (UUIDs are unique per creation).

Remaining risk: scalar/parts/maintenance edit races are still LWW — an honest, documented trade-off
of the whole-document bridge. Residual deletion limit: a deletion made by a client too old to write
tombstones (or lost with the document it lived in) can't be honored; only real history closes that.

Direction: event-based or operation-based sync with full history. Tombstones are the bridge's last
conservative step; per-field edit-race resolution needs real per-record timestamps/versioning. Still
the next major architectural item, but the highest-loss hole (resurrected deletes) is now closed.

## TD-002 — Test coverage expanding

Priority: Medium

Current state: 81 tests across model math, build-sheet parsing, cost/efficiency derivations, JSON
round-tripping, the full Steward ruleset (per-vehicle, fleet, live, briefing), evidence-band and
knowledge-state honesty (incl. incomplete-record false-positives), power basis, operating
envelopes, injected-clock determinism, OBD PID decoding, the ELM327 handshake state machine, and
the reusable stream lifecycle.

Risk: Hardware coverage is still incomplete — see TD-004 (multi-ECU/ISO-TP and live reconnect).
SwiftUI navigation and accessibility remain primarily manual/on-device. Recovery snapshot discovery,
versioned encoding, backward-compatible restore, unreadable-file refusal, and undoable restore are
covered by `RecoverySnapshotTests`.

Next steps: Add the remaining hardware-adjacent validation under TD-004 and expand focused SwiftUI
route/accessibility coverage where it can test behavior rather than implementation detail.

## TD-003 — Steward vocabulary exists conceptually, not in code

Priority: Medium

Current state: `BuildAdvisor` and `PurchaseManager` are early seeds of Steward-like behavior.

Risk: One-off managers could proliferate without a coherent Steward service boundary.

Next steps: Do not refactor prematurely. Watch for the third advisor-like service; that is likely the threshold for introducing a `Steward` namespace/boundary.
