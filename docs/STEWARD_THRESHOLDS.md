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
| Coolant caution / critical | **215 / 235°F**, or **nil (air-cooled)** | `StewardContext.swift`, `PlatformBaseline` | live coolant caution/advisory; suppressed entirely on air-cooled engines | `CONVENTION` — and now **physics-aware** (W-049): no coolant limit on a car with no coolant |
| Boost caution (boosted cars) | **per-platform, sourced** (S2000 13 · EJ turbo 17 · generic 16) | `PlatformBaseline.swift` | live "boost is high" caution when no owner ceiling is set | `SOURCED` (W-049) — was a flat-18 `GUESS`; now grounded in each platform's real tuning behavior with citations |
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
| Sequence-hazard window | **30 days** | `StewardThresholds.swift` | whether boost-ahead-of-fueling counts as running under-fueled | `OWNER` (Tim, 2026-07-18; was a `GUESS` 14) |
| Recent-pull window | **until resolved** | `Steward.swift` | how long a flagged pull stays actionable — now until a later clean pull resolves it, no timer | `OWNER` (Tim, 2026-07-18; retired the 14-day `GUESS` timeout) |
| Quiet-car window | **90 days** | `StewardThresholds.swift` | "you haven't touched this in a while" (informational) | `OWNER` (Tim, 2026-07-18; was a `GUESS` 180) |
| Mileage-change floor | **10 mi** | `FleetDigest.swift:60` | whether an odometer change is worth reporting since last visit | `GUESS` (harmless, but invented) |

## Pull intelligence (fleet-of-pulls trend)

| Threshold | Value | Where | Gates | Provenance |
|---|---|---|---|---|
| Strong on-target fit | **≥ 0.75** | `PullIntelligence.swift:123,194` | "this run hit its targets well" | `GUESS` |
| Band-measured floor | **≥ 0.40** | `PullIntelligence.swift:183` | whether a boost band is "measured enough" to judge | `GUESS` |
| Trend supermajority | **0.67** of pulls | `PullIntelligence.swift:196` | whether a drift trend is called consistent | `GUESS` |
| Peak-drift floor | **±0.75 psi** | `PullIntelligence.swift:194-195` | which pulls count toward a boost-drift trend | `GUESS` |

## Classifiers & heuristics (W-053)

Fable's re-review finding: **calibrating values while guessing classifiers just relocates the
guess.** The routes that decide *which* number applies to *which* car are judgment constants too,
and they belong in this register with the same provenance discipline. Every classifier must have an
owner override where the stakes justify one.

| Classifier | Rule | Where | Provenance / guard |
|---|---|---|---|
| Platform baseline matcher | make-anchored + substring + year window | `PlatformBaseline.baseline(for:)` | `SOURCED` per entry; make anchor + `yearMax` added after the matcher misrouted a 2005 Subaru Baja Turbo and a 2019 water-cooled Beetle to the air-cooled Type 1 entry |
| Air-cooled detection | catalog `airCooled`, OR the owner's own engine description says "air-cooled" | `Vehicle.isAirCooled` | safe direction: unknown ⇒ liquid-cooled (never silently suppress a coolant warning) |
| OBD-II support | owner override ?? (`!isAirCooled && year >= 1996`) | `Vehicle.supportsOBD2` | `OWNER`-overridable; the year rule is a US-mandate `CONVENTION` that is wrong for swapped classics and gray-market imports |
| Factory forced induction | owner override ?? engine text ("turbo"/"supercharg") + model markers (XT, WRX, STI, Evo, GTR, Mazdaspeed, Supra, SRT4) | `Vehicle.hasFactoryForcedInduction` | `OWNER`-overridable; marker list is a `GUESS` kept small on purpose |
| Elevated-boost gate | aftermarket FI, or factory FI + (calibration on record ∨ gain ≥ 1.25× stock baseline) | `Vehicle.runsElevatedBoost` | the 1.25 factor is a `GUESS` |
| Calibration-on-record | installed electronics part matching term list (tune, ecu, cobb, hondata, accessport…) | `Vehicle.calibrationTerms` | `GUESS` (term list); shared by tuner + boost gate so there's one definition |
| Well-documented record | ≥ 6 installed parts | `Vehicle.isWellDocumented` | `GUESS` |

## Verdict

One threshold (`450`) is owner-calibrated. A handful are defensible shop conventions. The **eleven
tagged `GUESS`** are plausible numbers with no grounding — and they wear the exact same authority in
the UI as the facts the app is so careful about elsewhere. That's the honesty gap Fable named: the
app grades *its inputs* by evidence but not *its own reasoning constants*.

### Calibrate first (consequence × arbitrariness)
1. ~~**Boost caution 18 psi**~~ — **DONE (W-049).** Replaced with sourced per-platform values
   (`PlatformBaseline`) and made physics-aware: NA cars get no boost caution, air-cooled cars get no
   coolant limit. The flat guess is gone.
2. ~~**Sequence/quiet windows 14 / 180 days**~~ — **DONE (W-050).** Owner-calibrated to 30 / 90 days, and the flagged-pull timeout replaced with "until resolved" (Tim, 2026-07-18). Now in `StewardThresholds`.
3. **Engine-internals gain 80 whp** (`BuildAssessment.swift:58`) — decides whether the app tells you
   your bottom end is a gap. A real number here would be per-platform, not a flat 80.

### Structural fix (recommended follow-up)
Centralize these into a single `StewardThresholds` with each constant's provenance tag in its own doc
comment, so a guess can't be added later without declaring itself, and calibrating one is a one-file
edit. Deferred as its own item to keep this audit zero-risk.
