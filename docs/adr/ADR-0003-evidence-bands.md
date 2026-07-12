# ADR-0003: Evidence Bands Instead of Numeric Confidence

## Status

Accepted (supersedes the numeric-confidence guidance in Constitution v1.0)

## Context

Early Steward observations displayed hand-authored confidence percentages (fueling gap 88%,
cooling 76%, cost-to-power 97%, and so on). These numbers were constants chosen by feel, not
calibrated probabilities. Displaying "CONFIDENCE 88%" implies a statistical grounding — outcome
labels, calibration data, false-positive analysis — that the system does not have. That is
worse than a descriptive grade, because it looks scientific while being arbitrary.

A related, deeper problem sat underneath the numbers: several rules treated a *missing logged
part* as evidence of a *missing physical system*, then attached a high percentage to that
inference. A fully built but incompletely documented car could receive a confident warning.

## Decision

Represent confidence as an **evidence band**, not a number:

```text
ConfidenceBand: confirmed > strong > moderate > weak > insufficient
```

The band is **derived from evidence completeness**, and pairs with an explicit knowledge model:

- `ComponentKnowledge`: `confirmedPresent`, `confirmedAbsent`, `undocumented`, `unknown`.
- A subsystem that is merely `undocumented` is reported as such ("hasn't been documented",
  WEAK/informational), never as absent. Only `confirmedAbsent` (the owner marked the factory
  system retained) earns a STRONG caution. An `.unknown` (empty/imported) record is silent.
- Derived arithmetic facts (elapsed days, undated-part counts) may be CONFIRMED; approximate
  ones (cost-per-hp across crank/wheel bases — see ADR-0004's sibling concern) are MODERATE.

Bands render as labels (`STRONG`) in the HUD and as phrases ("strong evidence") in speech.

## Consequences

Benefits:

- Honest: the interface claims only what the evidence supports.
- Safer defaults: incomplete records no longer generate confident false positives.
- A numeric confidence can be reintroduced later *if and when* calibration data exists — the
  band becomes the source of truth it would derive from.

Costs:

- Loses the numeric feel some users prefer. A hybrid (band + a number only where real math
  exists) remains available as a future option if bands read too clinically on device.
- Every rule and the display layer had to migrate from `Int` to `ConfidenceBand`.
