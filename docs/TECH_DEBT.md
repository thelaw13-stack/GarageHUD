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
path is still the offline fallback (a first-run nudge when only a default voice is installed —
`needsBetterVoiceDownload` — is wired but not surfaced). (2) Exercise the LLM path on an Apple-Intelligence device (iPhone
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

Remaining: a **pairing UI** (present discovered candidates, let the owner pick, persist the
returned profile, and load `knownPeripheralID` on next launch) — plumbing exists but is not yet
surfaced. And the hardware-dependent tests: real-adapter integration, ISO-TP/multi-ECU headers,
and live disconnect/reconnect against a device. See ADR-0004. Synthetic serial-transcript replay
is done (`OBDTranscriptReplayTests`).

## TD-005 — Schema versioning in persisted JSON — RESOLVED

Priority: Medium — done

Resolution: The local file is a versioned `GaragePersistence.Document { schemaVersion, vehicles }`
with a typed load result (`.ok` / `.migratedLegacy` / `.unreadable` / `.empty`). Legacy bare
arrays migrate in place; a corrupt file is backed up to `garage-unreadable-<ts>.json` and
surfaced via `GarageStore.loadFailureBackupURL` instead of being silently discarded. Covered by
`GaragePersistenceVersioningTests`. See [PERSISTENCE.md](PERSISTENCE.md).

Remaining: the CloudKit payload is still an unversioned bare array; version it too before any
non-additive change to the synced graph.

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
