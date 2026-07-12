# GarageHUD Architecture

## Current Shape

`GarageHUDKit` is the product core; app shells are thin wrappers around it. The
`GarageHUD-iOS` target compiles the package's sources directly (a file-system-synchronized
group) rather than linking a built product.

High-level boundaries under `Sources/GarageHUDKit/`:

- `Models/` — vehicle data, parts, events, notes, photos; live telemetry types
  (`LiveMetrics`, `LiveTelemetryFrame`, `TimedMeasurement`); evidence-state types
  (`ComponentKnowledge`, `PowerBasis`, `OperatingEnvelope`).
- `Persistence/` — local JSON persistence, CloudKit sync, image storage, purchase state,
  build-sheet parsing. See [PERSISTENCE.md](PERSISTENCE.md).
- `Steward/` — the reasoning engine (see below).
- `StewardVoice/` — speech input, conversation core, driving-mode policy, TTS session.
- `Live/` — OBD-II PID decoder, ELM327 handshake state machine, BLE transport.
- `Views/` — SwiftUI presentation.
- `DesignSystem/` — visual primitives and HUD styling.

## Source of Truth

`GarageStore` is the application source of truth for garage data. Views bind into
`GarageStore.vehicles`; persistence and sync remain behind the store. The model layer is plain
`Codable` structs (not SwiftData) — see [PERSISTENCE.md](PERSISTENCE.md) for why and for the
migration strategy.

## The Reasoning Layer (`Steward/`)

`GarageStore` owns memory; **Steward interprets it** and never owns truth. Every rule is a
**pure function of `(model, StewardContext)`** and emits `StewardObservation`s.

### StewardObservation

Each observation carries:

- `statement` / `evidence` — evidence-first language ("I observed… / The data suggests…").
- `confidence: ConfidenceBand` — `CONFIRMED / STRONG / MODERATE / WEAK / INSUFFICIENT`. An
  honest grade derived from evidence completeness, **not** a fabricated percentage (ADR-0003).
- `tone` — informational / caution / advisory.
- `provenance` — recorded / derived / estimatedLive / measuredLive.
- `ruleID` + `subjectID` — a **deterministic identity** (`"gap.fueling#<vehicle-uuid>"`), so
  recomputing a briefing yields stable ids and SwiftUI doesn't churn its diff.

Observations are sorted by a **total, tie-broken order** (severity, band, subject, ruleID) so
output never reshuffles between identical rebuilds.

### Evidence honesty — not-logged ≠ not-installed

`ComponentKnowledge` (`confirmedPresent / confirmedAbsent / undocumented / unknown`) is the
core guard. Absence of a logged part is **undocumented**, never reported as a missing physical
system. An empty/imported record is `.unknown` and produces no gap warnings. Only a
`confirmedAbsent` system (the owner marked it stock) yields a firm caution. (ADR-0003)

### Power basis

`PowerBasis` records whether a horsepower figure is `factoryCrank`, `measuredWheel`, etc.
Cost-to-power compares a measured wheel figure against a factory crank rating, so it is
explicitly labeled **approximate** and graded MODERATE — never presented as dyno-corrected
truth.

### StewardContext

`StewardContext { now, calendar }` is injected into every rule so day-count math (freshness,
neglect, sequence, stale-tune) is deterministic and testable. Production passes `.live`; tests
pass a fixed UTC clock. No rule reaches for `Date.now` or `Calendar.current` directly.

### Reasoning surfaces

- `Steward.observe(_:context:)` — per-vehicle rules.
- `Steward.observeFleet(_:context:)` — cross-car rules (value leader, neglect, confirmed shared
  gaps). Undocumented per-car gaps **never** aggregate into a fleet-level claim.
- `Steward.observe(frame:for:context:)` — live rules against the vehicle's `OperatingEnvelope`.
- `StewardBriefingBuilder.build(for:mode:limit:context:)` — the ranked garage rollup.

## Live Telemetry (`Live/`) — see ADR-0004

The Live HUD consumes a `LiveDataSource` that streams `LiveTelemetryFrame`s. Each metric is a
`TimedMeasurement` carrying its own timestamp and `MeasurementSource`. Consumers judge
**freshness** per metric against `LiveFreshness.window`; a value that stops arriving goes
*unavailable* rather than freezing at its last reading. A frame is **never** classified
"measured" as a whole — only the individual values decoded from an adapter this instant.

- `SimulatedLiveDataSource` — plausible values, always `.simulated`.
- `OBDLiveDataSource` — CoreBluetooth ELM327 client. Runs the **response-driven**
  `ELM327Handshake` state machine (one command in flight, advanced only on a prompt-terminated
  reply or a controlled timeout), then round-robins PIDs through the pure `OBDPIDDecoder`.
  Reusable lifecycle: `stop()` halts, `deinit` finishes the stream.

**Outstanding:** validated adapter profile, user pairing selection, and ELM327 identity
verification (TECH_DEBT). The transport compiles but is unproven against physical hardware.

## Sync Model

The garage graph is stored as a whole-document JSON payload on one private CloudKit record,
with photos as separate records; last-writer-wins with a conservative conflict guard. Rationale
and future direction: [ADR-0001](adr/ADR-0001-whole-document-sync.md) and
[PERSISTENCE.md](PERSISTENCE.md).

## Voice (`StewardVoice/`) — see ADR-0002

The conversation core (`StewardConversation`) is pure and synchronous; `StewardVoiceSession`
wraps it with `SFSpeechRecognizer` capture and `AVSpeechSynthesizer` TTS. **Driving mode** is
the safety-critical policy: while `.moving`, answers shorten to a single sentence and the
briefing drops everything below advisory. The `.moving` branch is a builder parameter that
callers must pass explicitly — motion is **not** inferred from GPS without a hysteresis-guarded
policy (still to be built).

## Future Direction

Move gradually toward event-centric vehicle memory (the timeline spine is the first step) and
per-event sync as history grows — without a rewrite today. Steward should keep reasoning over
vehicle memory, fleet memory, provenance, confidence, context, and owner goals.
