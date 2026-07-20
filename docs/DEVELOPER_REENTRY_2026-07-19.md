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

## Addendum — later the same day (2026-07-19)

Everything above describes `main` at `43635eb` and remains an accurate record of that moment. This
section records what changed after it, so the brief doesn't quietly go stale.

`W-013` is **complete**. The conversational Steward was validated on Tim's phone with him present:
the on-device model resolves, answers in ~1.2s, and refuses out-of-record questions cleanly. Two
real failures surfaced and were fixed and re-validated the same session:

- **W-061** — asked how much power the car makes, the Steward added the ~201 whp "gained over stock"
  estimate to the 381 whp measured figure. The gain is *derived from* the measurement, so it was
  already inside it; the record listed the two as adjacent siblings with no stated relationship and
  nothing forbade arithmetic. The grounding record now names the containment and the instructions
  forbid combining recorded values. The same latent trap existed in the Investment section and was
  labelled too.
- **W-062** — the second mic tap stopped listening without sending, because `stop()` cancels the
  recognition task before the `isFinal` result that triggers submission can arrive. The gesture was
  destroying its own outcome. A user-initiated stop now submits what was transcribed.
- **W-063** — the phone slept during live sessions; nothing ever requested wake. Now driven by
  session state and released on stop.

`W-060` holds cloud-voice validation, **blocked by owner decision rather than capability**: Tim
declined a paid voice key so GarageHUD stays free to run. The path is verified inert (config
defaults off, no key stored). Do not "fix" this by spending money.

`TD-001` now has a design: [ADR-0005](adr/ADR-0005-per-record-sync-model.md), status Proposed,
tracked as `W-064` and blocked on Tim accepting or amending the coherence grouping. Read the two
traps in it before writing any sync code.

**Deploy note:** build **Debug** for Tim's phone. Release sets `AppIcon` and silently replaces the
papaya dev icon with the production one — that happened today. `WORKLIST.json`'s `device_deploy`
has been corrected accordingly.

One pattern worth carrying forward: both bugs found today were bugs of *adjacency*, not of any
individual value. Every line of the grounding record was true; what lied was two true facts sitting
next to each other. ADR-0005 argues the same shape is waiting in field-level sync merge. When
reviewing this codebase, check what two correct things mean together.

## Safe first move

Pull `main`, run the package suite, read the latest `WORKLIST.json`, and coordinate ownership before
editing persistence or OBD transport. For an immediately useful next task, design the timestamped
per-record sync model on paper and migration tests first, or continue `W-014` only with Tim and the
physical adapter present.
