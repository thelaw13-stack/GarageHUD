# Design Debt Register

## DD-001 — Eye gravity review

Every major screen should be reviewed with one question: where does the eye land first?
If two reviewers answer differently, the hierarchy is not finished.

### First-reviewer pass (Vector, 2026-07-16)

Reviewed from a live Simulator screenshot (Garage) and from the view code (Dashboard, Specs, Ask
Steward). Vehicle: the seeded out-of-service S2K. Awaiting Tim's second-reviewer read — where two
answers differ, the item stays open.

**Garage (front door).** Eye lands: `GARAGE` (largest) → the cyan `Brief me` CTA → the hero car +
its amber `OUT OF SERVICE`. Anchor is the car, so the three-layer vision holds. Findings:

- **F1 — fleet-health strip clipped its last stat. FIXED.** Four long labeled stats couldn't fit one
  line, so a horizontal scroll hid `SERVICE DUE` (read as a broken "2 S…"). Now wraps to two rows
  (`ViewThatFits`) so nothing is hidden; unchanged when it does fit. Verified on device.
- **F2 — power competes with state on an out-of-service car (for Tim).** The hero instrument rail
  shows `POWER 477 WHP` in bright cyan next to amber `OUT OF SERVICE` and red `TUNE STATE HOLD` —
  three signal colors in one glance. For a torn-down car, power isn't the story; consider dimming
  POWER to `textPrimary` (reserving cyan for when power *is* the headline) while out of service.
- **F3 — the active car appears twice (for Tim).** It's the hero (BAY 1) *and* the first row of the
  vehicle list directly below. Consider omitting the spotlighted car from the list.
- **F4 — top-right crowding (verify on device).** The rightmost bay tab and the hero's open-arrow
  button look close/overlapping in the top-right; nudge spacing if it's a real collision.

**Dashboard (per-car cockpit).** Panels stack identity → build assessment → Build Plan → maintenance
→ … Car-first holds, but "the condition" (what matters *now*) can fall below the fold on a busy car.
Consider a one-line condition summary directly under identity. (Log; softer.)

**Specs.** Post-consolidation it's one calm Numbers panel (POWER → INVESTMENT → OWNERSHIP). Eye lands
on the section it's scrolled to; hierarchy reads clean. No finding.

**Ask Steward.** Eye lands on the reply panel, then the mic. Reasonable; the voice nudge sits quietly
under the header when applicable. No finding.

Status update (2026-07-17): F2 (dim POWER while out of service), F3 (spotlighted car omitted from
the grid), and F4 (BAY label moved clear of the open-arrow) all landed — W-018/W-019/W-020,
verified in the simulator. Tim's second-reviewer read confirmed the related power-labeling work on
device ("i dont have an un recorded power level"). Still open: the Dashboard condition-summary
idea (softer), and DD-001 remains a standing rule for every new screen.

## DD-002 — Driving Mode interaction model

Live telemetry cannot rely on typing or dense touch targets during active use.

Future review should define the minimum safe in-motion interface and voice command set.

## DD-004 — One gesture, one response (standing rule)

From Tim, 2026-07-18, after watching himself fight the NEXT line: "as a fundamental principle —
excess motion, user confused, not intuitive. If you were at Microsoft observing the user, you
would have seen me say fuck this app."

The rules, binding on every future control:

- **One gesture → one response shape, everywhere.** A tappable row does the same kind of thing
  wherever it appears. In GarageHUD that thing is the standard resolution dialog.
- **Never auto-scroll or jump the view as a tap response.** Motion only when the user explicitly
  asked to go somewhere. Motion explains; it never decorates.
- **No conditional affordances.** A control that acts on one car and is dead on another reads as
  broken. Either it always acts, or it is not styled (or shown) as a control at all.
- **Boring beats clever.** Prefer removing an element over teaching the user a new affordance.
  When in doubt, ship the boring version and ask Tim before the clever one.
- **Batch UI changes into one deploy.** Repeated patch-deploy rounds on one control are
  themselves excess motion.

## DD-003 — Steward tone

Steward should be calm, humble, evidence-based, and concise. It should never manufacture urgency or pretend certainty.

Internal motto: Observe first. Advise second.
