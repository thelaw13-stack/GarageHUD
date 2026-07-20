# ADR-0006: A Provenance Spine — Confidence That Can Only Decrease

## Status

**Accepted** — 2026-07-20, by Tim, all three decisions as recommended:
1. Humble default — a typed number is `estimated` until deliberately promoted. **Yes.**
2. `unknown` as a first-class, comfortable choice so placeholders stop happening. **Yes.**
3. Scope — **load-bearing figures only.**

Implementation tracked as W-073; supersedes the standalone W-070/W-071/W-072, which become the three
acceptance cases it must satisfy.

## Context

GarageHUD enforces honesty everywhere a value is *shown* — evidence bands, "measured" vs "est"
wording, the cross-surface honesty sweep — and nowhere a value is *created*. Three field-found
gaps, all the same shape:

- **W-070** — the Baja's `75 hp` is a placeholder Tim typed to fill the field. It is stored in
  `factoryHorsepower` as a bare `Double`, identical to a figure read off a spec sheet, and then
  seeds `estimatedStockWheelHP` (63 whp), power-to-weight, and cost-per-hp. One guess becomes
  several derived numbers, each wearing a band it never earned.
- **W-071** — the fleet sheet stacks a crank-hp headline (`75 hp est`) directly over a wheel-hp
  baseline (`63 whp`). Two units presented as a comparable pair, reading as "down from 75 to 63".
- **W-072** — the Baja's `$8,000` acquisition cost was entered as build investment. Every downstream
  surface honours the three-money-facts rule; nothing guards the point of entry. (Now corrected by
  hand, but the trap remains for the next value.)

These are not bugs in the sense of wrong code. `totalInvested` faithfully reported the field it was
given; the estimate was labelled weak exactly as designed. The gap is architectural: **a value's
origin is lost the instant it becomes a number, so nothing downstream can tell a measurement from a
guess, and a derivation can quietly launder one into the other.**

This is the same failure the app already guards against for *records* — the re-entry brief's rule 2,
"missing is not absent: preserve confirmed-present, confirmed-absent, undocumented, and unknown." That
doctrine exists for the presence of facts. It has no equivalent for the *provenance of a value*.

## Decision

One principle, enforced at three points.

> **Provenance travels with a value — from entry, through every derived figure, to every display —
> and confidence can only ever decrease along that path, never increase.**

### 1. A small, closed provenance vocabulary

Attached to load-bearing numeric figures, ordered weakest to strongest:

| Provenance | Meaning | Example |
|---|---|---|
| `unknown` | Not recorded. The honest blank. | a spec never entered |
| `estimated` | The owner's approximation. Honest, but claims no source. | "roughly 75 hp" |
| `sourced` | Transcribed from a real reference. | window sticker, build sheet, factory spec |
| `measured` | From an instrument. | a dyno pull |

This is distinct from the existing **evidence band** (Confirmed/Strong/…/Insufficient), which is about
*precision*. Provenance is about *origin*. A dyno figure is `measured` + Strong; a typed guess is
`estimated` + Insufficient. Provenance is the thing W-070 found missing — the band alone can't tell a
loosely-held spec from an invented one.

### 2. The humble default — a typed number is `estimated`, never `sourced`

The fix for W-070's root cause, and it needs **no picker and no form**. A number the owner types is
`estimated` by default: it claims no source, because typing one isn't a source. To mark a figure
`sourced` or `measured` is a *deliberate* act — you assert the window sticker, you don't get it for
free by typing. A pure guess and an informed estimate both land as `estimated`, which is honest for
both — neither is pretending to be documented.

This inverts today's implicit default (a typed number is treated as good as any other) into an
honest one (a typed number is only ever the owner's estimate until deliberately promoted).

### 3. `unknown` becomes comfortable, so placeholders stop happening

Tim typed `75` because the field looked like it wanted a number. If leaving it **unknown** were a
first-class, unembarrassing choice — and the app reasoned gracefully from unknown (no fabricated
baseline, an honest "not recorded", the same way `unknown price is not zero`) — the placeholder never
gets typed. This is the root-cause half of W-070: the other half (marking the ones that *are* typed)
is handled by the humble default above.

### 4. The monotonic rule — derivations can only lose confidence

A derived figure inherits the **weakest** provenance among its inputs, and is displayed with no more
confidence than that input earned. `estimatedStockWheelHP` derived from an `estimated` 75 hp is
itself `estimated` — so the fleet sheet's "STOCK BASELINE 63 whp" can never render as a hard number;
it reads as an estimate or is suppressed. This is the anti-laundering rule, and it is exactly what
W-071 needs too: a crank estimate and a wheel figure can't be stacked as a confident comparison,
because the comparison is only as strong as its weakest term.

### 5. Money carries category at entry (W-072)

The three money facts — acquisition, build, service — are already separate fields. Entry makes the
distinction obvious *at the point of typing* rather than only downstream, so an acquisition cost can't
land in the build slot. This is provenance-of-meaning rather than provenance-of-confidence, but it's
the same spine: capture what a number *is* when it's created, not after.

## Scope

**Load-bearing figures only** — the ones that seed derivations or drive money/power reasoning:
`factoryHorsepower`, `factoryTorque`, `factoryWeightLbs`, `purchasePrice`,
`documentedTotalInvestment`. Measured dyno figures already carry provenance via their record type.
Everything else (nicknames, colours, free text) is out of scope — provenance on a nickname is noise.

## Migration

- Existing unmarked values decode as **`unspecified`**, rendered exactly as they are today. **No
  value is retroactively cast into doubt** — an owner's years of data don't suddenly all read as
  guesses. `unspecified` reasons like the current behaviour: honest about precision via the existing
  band, silent about origin.
- Only values *entered or edited after* this ships carry real provenance. The spine grows forward.
- Additive schema bump, following the ADR-0005 precedent (absent field → `unspecified`).

## Consequences

Benefits:
- A guess can never again masquerade as a measurement, or launder itself into one through a
  derivation.
- The fleet sheet stops presenting estimated baselines as hard numbers.
- `unknown` becomes a first-class answer, so the app stops pressuring owners into placeholders.

Costs, honestly:
- Every load-bearing figure gains a provenance field and every derivation that reads it must thread
  it through. This is invasive in the reasoning layer — it's the honesty spine, so it reaches
  everywhere the spine does.
- Get the default wrong and every figure reads as doubtful, which is worse than the problem. The
  humble default (§2) and the no-retro-doubt migration (§Migration) exist precisely to avoid that.
- Provenance is metadata the owner mostly won't see. It earns its place only because it changes what
  the app is *allowed to claim*, never as decoration.

## Decisions for Tim

1. **The humble default (§2).** A number you type is treated as your *estimate* until you
   deliberately mark it sourced/measured — no form, just an honest default. Accept, or would you
   rather a value stay `unknown` until you pick a provenance (safer, but adds a step to every entry)?
2. **`unknown` as first-class (§3).** Make "I don't know this yet" a comfortable choice that reasons
   gracefully, so placeholders stop happening. Accept?
3. **Scope (§Scope).** Load-bearing figures only, or wider?

Everything else follows from these three.
