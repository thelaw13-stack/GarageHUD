# Contributing to GarageHUD

GarageHUD is developed by a small team — Tim (owner) plus AI collaborators working in parallel.
These conventions keep that parallel work coordinated and keep `main` always green and shippable.

## Start here, every session

**Read [`WORKLIST.json`](WORKLIST.json) first — before touching code.** It is the durable plan of
record: completed work with its evidence (commit + test delta), and open work with explicit
completion and testing criteria. Follow its `session_protocol` — pick the next unblocked item whose
dependencies are `complete`, set it `in_progress`, meet every completion criterion, run the tests,
then record the result and set `status`. Never mark an item `complete` without a recorded, passing
test result. The scoreboard, not memory, defines the current state.

## The golden rule

**`main` is always green.** Never commit code that doesn't build clean and pass every test. There
is no "I'll fix it in the next commit."

Before **every** commit:

```bash
cd GarageHUDKit
swift build 2>&1 | grep -cE "error:|warning:"   # must print 0
swift test                                       # all tests must pass
```

The project holds a **zero-warning bar** (`-strict-concurrency=complete`). A new warning is a
failing build.

## Commit conventions

- **Subject line:** imperative mood, ≤ ~72 chars, no trailing period.
  `Add mileage-based maintenance intervals` — not `Added…` / `Adds…`.
- **Body:** explain the *why* and the *what changed*, wrapped ~90 cols. State the test delta
  (`214 tests green (+3)`) and call out any deliberate behavior change or migration concern.
- **Trailer:** AI-authored commits end with
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` (or the relevant model).
- **One logical change per commit.** A view refactor and a model fix are two commits.
- **Tests ship with the code that needs them**, in the same commit — never "tests later."

## Incomplete or unvalidated work

Nothing half-finished lands silently. Use one of:

1. **`[WIP]` tag** in the commit subject for work intentionally left incomplete on a branch
   (`[WIP] External Accessory transport for MX+`). WIP commits do **not** go on `main`.
2. **A `TD-xxx` entry** in [`docs/TECH_DEBT.md`](docs/TECH_DEBT.md) for a known gap that ships
   anyway (e.g. logic that's tested but not yet exercised on real hardware). This is the primary
   tracker — see TD-004 (adapter pairing/hardware validation) and TD-007 (voice/LLM on-device
   validation) as the models. Reference the `TD-xxx` id from the README "Status & known gaps."
3. **A GitHub issue** when the item is discrete and assignable. *(As of this writing the repo is
   tracked via the `TD-xxx` register rather than issues; adopt issues + the project board below as
   the team grows.)*

Never present unvalidated behavior as verified. If a path compiles but hasn't run on device,
say so in the commit body and the relevant `TD-xxx`.

## Branches, PRs, and reconciling parallel work

The current cadence is **small branches merged through tested pull requests** so the other
developer can see, review, and safely build every change. Because multiple developers work in
parallel:

- **Before pushing**, `git fetch origin` and reconcile. If `main` advanced, **rebase** your local
  commits onto `origin/main` (our commits rarely touch the same files, so this is almost always
  clean). Re-run `swift build` + `swift test` after the rebase before pushing.
- **Use a feature branch + PR** for product changes. Branch names: `codex/<topic>` or
  `<topic>-<detail>`.
- **Coordinate the wheel.** Only one developer should be actively editing a given area at a time —
  parallel edits to the same files are how work gets clobbered. Confirm who's driving before a big
  push.

### PR conventions (when used)

- **Title:** same imperative style as a commit subject; prefix `[WIP]` while in progress.
- **Description:** what changed, why, the test delta, and how it was verified (build/test/on-device).
- **Green before merge:** package tests and both iOS simulator configurations must pass. A merge
  commit is acceptable when it preserves a visible PR boundary and its validation record.
- **Link the `TD-xxx`** or issue the PR addresses.

## Verifying a change

- **Logic** → unit tests in `GarageHUDKit/Tests`. Pure, deterministic, fast. Model/reasoning
  changes are not "done" without tests.
- **UI / on-device** → build the Release config and install to a device; note what you observed in
  the commit. The iOS app depends on the local `GarageHUDKit` SwiftPM package, so new Swift files
  are picked up automatically (the `.pbxproj` uses filesystem-synchronized groups — you rarely
  touch it, which keeps merges conflict-free).

```bash
# iOS Release build + install (device unlocked)
xcodebuild -project GarageHUD-iOS/GarageHUD.xcodeproj -scheme GarageHUD \
  -configuration Release -destination 'platform=iOS,id=<DEVICE_ID>' -allowProvisioningUpdates build
xcrun devicectl device install app --device <DEVICE_ID> <path-to>/GarageHUD.app
```

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on every push to `main` and every PR:

- **`package-tests`** — `swift build` + `swift test`, emitting JUnit results uploaded as a build
  artifact so a PR's test outcomes are inspectable, not just pass/fail.
- **`ios-build`** — builds the app for the iOS Simulator (no signing) to catch app-target breakage
  the package tests can't.

A PR is not mergeable until both are green.

## Docs map

- [`README.md`](README.md) — what it is + "Status & known gaps."
- [`docs/CONSTITUTION.md`](docs/CONSTITUTION.md) — the product principles (evidence-led, honest,
  "the car first"). Read this before changing Steward behavior or copy.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — how the layers fit.
- [`docs/TECH_DEBT.md`](docs/TECH_DEBT.md) — the `TD-xxx` register (**the** known-gaps tracker).
- [`docs/DESIGN_DEBT.md`](docs/DESIGN_DEBT.md) — visual/UX debt.
- [`docs/adr/`](docs/adr/) — architecture decision records.

## Project board (recommended setup)

Track the "Status & known gaps" as a GitHub Project (Board view), seeded from the `TD-xxx`
register. Suggested columns and starting cards:

- **Backlog** — TD-001 (whole-document CloudKit sync hardening)
- **Needs on-device validation** — TD-004 (adapter pairing/hardware), TD-007 (voice/LLM on device)
- **In progress** — whatever's actively being built
- **Done** — TD-005, TD-006 (resolved)

Automate: move a card to *Done* when its `TD-xxx` is marked RESOLVED in `TECH_DEBT.md`, or when the
linked PR merges. *(The board is created via the GitHub UI / API and isn't checked into the repo.)*
