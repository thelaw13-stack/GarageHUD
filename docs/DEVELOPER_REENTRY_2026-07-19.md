# GarageHUD Developer Re-entry — 2026-07-19

Welcome back. Tim asked Codex to take the wheel while you were away. All work landed through
reviewable pull requests; `main` is the only product line, and GarageHUD2 remains stale/out of
scope. Start with `WORKLIST.json`, then this note, then `docs/TECH_DEBT.md`.

## Where main stands

- Repository: `thelaw13-stack/GarageHUD`
- Main before this handoff: `2c3a13e`
- Verification: 465 Swift package tests pass with warnings as errors; Debug and Release iOS
  Simulator builds pass.
- The current signed Debug build is installed and launched on Tim's iPhone 15 Pro Max.
- Development builds use the distinct car-first papaya/purple icon; production keeps its normal
  icon.

## What landed

PR #1 (`deep-review-fixes`) hardened CloudKit failure truth, conflict retry reporting, future-schema
refusal, deterministic Steward fallback time, OBD bind diagnosis, and CI. PRs #2–#3 completed the
macOS development icon sizes and made the race car visually dominant over the cyan eye. PR #4
versioned conflict and pre-restore recovery snapshots while retaining legacy restore support. PR
#5 collapsed consecutive duplicate OBD journal transitions found in the successful field report.
PR #6 codified the record/Steward/assistant truth boundary and corrected stale status docs.

The sync bridge already on main preserves append-only records and uses deletion tombstones.
Recovery copies are preserved and owner-visible rather than silently discarded. Dyno input and
wheel-vs-crank labels have adversarial regression coverage. Focused Steward actions, evidence
bands, injected clocks, and per-measurement telemetry freshness remain foundational invariants.

## OBD-II field truth

The Veepeak OBDCheck BLE path is no longer theoretical. Two independent July 19 sessions proved
advertisement discovery, FFF0/FFF1/FFF2 serial binding, notification subscription, ELM identity,
configuration, supported `41 00` response, polling, and decoded measured data in 2.4 and 2.7
seconds. The latest session remained measuring for 503.6 seconds and ended with an intentional
STOPPED event, not a disconnect.

Do not destabilize the proven handshake without a field report and a regression test. Still
unverified: a genuine mid-session disconnect/reconnect and multi-ECU/ISO-TP hardware behavior
(`W-014`, `TD-004`).

## Highest remaining risk

`TD-001` remains the architectural priority. Whole-document CloudKit adoption is now conservative,
append-preserving, and tombstone-aware, but concurrent scalar, part, and maintenance edits are
still last-writer-wins. The next serious sync step needs real per-record timestamps/history; do not
guess winners from array order or device time without an explicit design and migration tests.

`W-013` remains honestly blocked on real credentials/hardware validation for cloud voice,
Foundation Models, and microphone speech-in. Do not mark it complete from simulator behavior.

## Rules that must survive future work

1. The vehicle record owns truth. Steward interprets; assistants explain. Neither invents or
   directly mutates facts.
2. Missing is not absent. Preserve confirmed-present, confirmed-absent, undocumented, and unknown.
3. Every actionable warning needs a direct evidence view and focused resolution door.
4. Purchase price, build investment, and service spend never collapse into one number; unknown
   prices are not zero.
5. Telemetry quality belongs to each value. Stale values become unavailable, never frozen as live.
6. A feature is done only with deterministic behavior, tests, an obvious route, readable iPhone
   layout, and visible state change after save.

## Design candidate

`docs/design/icon-candidate-flair-v2.png` is the approved source for the development icon. It keeps
the centered papaya Formula-style car dominant, the cyan eye secondary, and adds restrained purple
atmosphere plus cyan/papaya speed arcs. Tim approved candidate #1; its 16–1024px derivatives are
wired into `AppIconDev.appiconset`. The production icon remains unchanged.

## Safe first move

Pull `main`, run the package suite, read the latest `WORKLIST.json`, and coordinate ownership before
editing persistence or OBD transport. For an immediately useful next task, design the timestamped
per-record sync model on paper and migration tests first, or continue `W-014` only with Tim and the
physical adapter present.
