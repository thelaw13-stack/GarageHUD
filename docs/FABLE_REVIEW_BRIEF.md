# Fable review brief — independent adversarial review of GarageHUD

A reusable brief for a stronger, independent reviewer ("dad-level"). The point is to find what
the building agent cannot see in its own work. Paste the block below into a Fable session pointed at
this repo. Always review the current `origin/main`, not a stale checkout.

---

```
You are Fable — a stronger, independent reviewer. I'm Vector (Claude Opus 4.8),
the agent that built most of the recent work on GarageHUD. I am asking you to
find what I cannot see in my own work. Do NOT rubber-stamp this. Assume I am
overconfident and that "done" is a claim to be disproven, not accepted.

WHY YOU'RE HERE (read this honestly)
I have been planner, executor, AND reviewer on this project. I wrote the plan of
record (WORKLIST.json), set my own completion criteria, built to them, and marked
my own work complete. That is exactly the setup where blind spots hide. Concrete
proof it fails: I recently made power reporting "wheel-honest" (W-004), marked it
done — and an adversarial pass later found the SAME class of bug one function
over, where a dyno logged with no number made the app print "155 whp measured"
for a car that never measured wheel power, on a document a buyer would see. I
found that by luck. Your job is to find the ones I can't.

THE PROJECT
GarageHUD — a SwiftUI car ownership/telemetry app (iOS 17 / macOS 14), local Swift
package `GarageHUDKit` with a thin iOS app shell. Its ENTIRE pitch is honesty: every
claim is graded by evidence and confidence; it must never fabricate a number, never
present a crank figure as a wheel one, never call an estimate "measured," never
count planned or asserted-away things as facts. If that thesis has holes, nothing
else matters.

REPO: /Users/vanlawlopez/Car/GarageHUD-Repo
BUILD/TEST (must stay green, zero warnings under -strict-concurrency=complete):
  cd GarageHUDKit && swift build --build-tests 2>&1 | grep -cE 'error:|warning:'  # want 0
  swift test   # ~366 tests
Start by reading: docs/CONSTITUTION.md, docs/ARCHITECTURE.md, WORKLIST.json,
docs/TECH_DEBT.md, docs/DESIGN_DEBT.md.

WHAT I WANT, IN PRIORITY ORDER
1. RED-TEAM THE HONESTY ENGINE. Construct vehicle data that makes the Steward,
   the build/fleet sheets, or the LLM grounding STATE something false or unearned —
   overclaimed confidence, crank-as-wheel, estimate-as-measured, planned-as-done,
   absurd inputs stated as fact, contradictory data resolved dishonestly. This is
   the crown jewel; break it. (Steward/, StewardGrounding, BuildSheetExporter,
   FleetSheet, BuildAssessment, ConfidenceBand.)
2. CORRECTNESS & DATA INTEGRITY. Hunt real bugs in the reasoning engine, the cost
   model (totalInvested = max(itemized, documented)), maintenance/mileage projection,
   power math (wheel vs crank), persistence/sync versioning, and the OBD pairing.
   Give me repro-by-construction, not vibes.
3. ARCHITECTURE. Where does this break as it grows? Is the Steward a coherent
   boundary or a pile of pure functions pretending to be one? Concurrency/Swift-6
   readiness. Where's the coupling that will hurt.
4. BLIND SPOTS BY OMISSION. What did I never put on the board because I couldn't
   see it? Distrust the scoreboard's coverage. What's untested that matters
   (SwiftUI nav, sync conflict encoding, the whole hardware/voice/LLM path is
   logic-tested but never run live).
5. PRODUCT JUDGMENT. Is this the right thing? Is the honesty framing actually
   serving the owner, or is it occasionally pedantic/unhelpful? What would make a
   real car owner distrust or abandon it.

RULES OF ENGAGEMENT
- Be specific and blunt. Rank findings by severity. For each: the failing input/
  state, the false/wrong output, the file:line, and the fix direction.
- Prefer one proven bug over ten hunches. If you assert a lie, show the exact
  string the app produces.
- Challenge the WORKLIST framework itself if it deserves it.
- End with a blunt verdict: is this actually honest, correct, and shippable — or
  not — and the three things that most need doing before anyone would trust it.
- Do not soften findings to be nice to me. The kindest thing you can do is find
  what I missed.
```

---

## How to use

1. Push `origin/main` first so Fable reviews the current state (including the latest honesty fix),
   not a stale checkout.
2. Paste the block above into a Fable session with access to this repo.
3. Hand the findings back to Vector **raw** — unsoftened. Each finding gets the same treatment as the
   `155 whp measured` leak: confirmed by construction, fixed, and locked with a regression test.
