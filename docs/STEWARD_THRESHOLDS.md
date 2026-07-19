# Steward threshold provenance register

The app's pitch is that it never states a guess as a fact. This register turns that lens on the
reasoning layer itself. Every judgment threshold below is a number that decides what the Steward
says — and almost all of them are numbers someone typed, not numbers the owner calibrated. The point
of this document is that the guesses stop hiding among the facts.

**Provenance tags**
- `OWNER` — a value the owner (Tim) explicitly set or confirmed for this fleet.
- `CONVENTION` — a widely-accepted shop/industry figure. Defensible, but not tuned to these cars.
- `GUESS` — a plausible number typed with no external grounding. These are the ones to distrust.

Last swept: 2026-07-16 (W-048), against the reasoning layer at this commit.

## Power / build coherence

| Threshold | Value | Where | Gates | Provenance |
|---|---|---|---|---|
| Driveline-attention wheel HP | **450** | `ComponentKnowledge.swift:188` | when a build "makes real power" (clutch/brakes/driveline relevant; NEXT-step wording) | `OWNER` — Tim set 450 (W-044), replacing an invented 40 |
| Engine-internals relevance gain | **80 whp** over stock | `BuildAssessment.swift:58` | whether "engine internals" appears as a load-bearing subsystem on a boosted car | `GUESS` |
| Drivetrain loss fraction | FWD .10 / RWD .15 / AWD .20 / unknown .15 | `ComponentKnowledge.swift:55` | crank→wheel stock baseline, and therefore every "over stock" gain figure | `CONVENTION` (shop rule-of-thumb; real losses vary by car) |

## Live telemetry limits (OperatingEnvelope defaults)

| Threshold | Value | Where | Gates | Provenance |
|---|---|---|---|---|
| Coolant caution | **215°F** | `StewardContext.swift:63,87` | live "coolant getting warm" caution | `CONVENTION` (leans conservative) |
| Coolant critical | **235°F** | `StewardContext.swift:63,87` | live "coolant is hot" advisory | `CONVENTION` |
| Boost caution (boosted cars) | **18 psi** | `StewardContext.swift:88` | live "boost is high" caution when no owner ceiling is set | `GUESS` — a single number applied to every boosted car regardless of setup |
| Pull coolant-rise flag | **≥ 15°F** delta | `PullIntelligence.swift:74` | "the car heat-soaked during that pull" | `GUESS` |

Note: `maxSustainedBoostPsi` (the hard over-boost ceiling) is `OWNER`, opt-in — the one live limit
that's honest by construction, because the owner sets it.

## Maintenance timing

| Threshold | Value | Where | Gates | Provenance |
|---|---|---|---|---|
| Time due-soon window | **30 days** | `MaintenanceItem.swift:85`, `FleetHealth.swift:69` | "service due soon" vs "ok" | `CONVENTION` |
| Mileage due-soon window | **500 mi** | `MaintenanceItem.swift:93`, `BuildSheetExporter.swift:98` | mileage "due soon" | `CONVENTION` |

## Timeline / sequence reasoning

| Threshold | Value | Where | Gates | Provenance |
|---|---|---|---|---|
| Sequence-hazard window | **14 days** | `Steward.swift:46` | whether two out-of-order installs count as a "fueling-after-boost" sequence flag | `GUESS` |
| Recent-pull window | **≤ 14 days** | `Steward.swift:144` | whether a flagged pull is "recent" enough to surface | `GUESS` |
| Quiet-car window | **≥ 180 days** | `Steward.swift:158` | "you haven't touched this in a while" | `GUESS` |
| Mileage-change floor | **10 mi** | `FleetDigest.swift:60` | whether an odometer change is worth reporting since last visit | `GUESS` (harmless, but invented) |

## Pull intelligence (fleet-of-pulls trend)

| Threshold | Value | Where | Gates | Provenance |
|---|---|---|---|---|
| Strong on-target fit | **≥ 0.75** | `PullIntelligence.swift:123,194` | "this run hit its targets well" | `GUESS` |
| Band-measured floor | **≥ 0.40** | `PullIntelligence.swift:183` | whether a boost band is "measured enough" to judge | `GUESS` |
| Trend supermajority | **0.67** of pulls | `PullIntelligence.swift:196` | whether a drift trend is called consistent | `GUESS` |
| Peak-drift floor | **±0.75 psi** | `PullIntelligence.swift:194-195` | which pulls count toward a boost-drift trend | `GUESS` |

## Verdict

One threshold (`450`) is owner-calibrated. A handful are defensible shop conventions. The **eleven
tagged `GUESS`** are plausible numbers with no grounding — and they wear the exact same authority in
the UI as the facts the app is so careful about elsewhere. That's the honesty gap Fable named: the
app grades *its inputs* by evidence but not *its own reasoning constants*.

### Calibrate first (consequence × arbitrariness)
1. **Boost caution 18 psi** (`StewardContext.swift:88`) — one number for every boosted car is wrong
   for most of them. A stock-turbo Fozzy and a built S2K don't share a caution point. Highest
   consequence (it's a *safety* caution) and highest arbitrariness. Should be per-car, like the
   ceiling already is.
2. **Sequence/quiet windows 14 / 180 days** (`Steward.swift`) — these decide whether the Steward
   speaks at all about sequence and dormancy; wrong values make it nag or go silent at the wrong time.
3. **Engine-internals gain 80 whp** (`BuildAssessment.swift:58`) — decides whether the app tells you
   your bottom end is a gap. A real number here would be per-platform, not a flat 80.

### Structural fix (recommended follow-up)
Centralize these into a single `StewardThresholds` with each constant's provenance tag in its own doc
comment, so a guess can't be added later without declaring itself, and calibrating one is a one-file
edit. Deferred as its own item to keep this audit zero-risk.
