# GarageHUD

[![CI](https://github.com/thelaw13-stack/GarageHUD/actions/workflows/ci.yml/badge.svg)](https://github.com/thelaw13-stack/GarageHUD/actions/workflows/ci.yml)

A "Jarvis HUD"-styled car-inventory and telemetry app for **macOS + iPhone**, tracking an
enthusiast's fleet — parts, build history, dyno results, photos, and live OBD-II telemetry —
with **CloudKit sync** across devices. Its intelligence layer is **Fleet Steward**, a reasoning
engine that observes recorded data and advises with honest, evidence-graded confidence.

> GarageHUD records. Fleet Steward understands. See the [Constitution](docs/CONSTITUTION.md).

## Repository layout

```text
GarageHUD-Repo/
├── README.md                 ← you are here
├── docs/                     ← durable system specification
│   ├── ARCHITECTURE.md       ← boundaries, source of truth, reasoning + telemetry model
│   ├── CONSTITUTION.md       ← product philosophy and Steward doctrine
│   ├── PERSISTENCE.md        ← storage model, sync, and migration strategy
│   ├── TECH_DEBT.md / DESIGN_DEBT.md / FUTURE.md
│   └── adr/                  ← Architecture Decision Records (ADR-0001…)
├── GarageHUDKit/             ← the product core (Swift Package; all logic + SwiftUI)
│   ├── Sources/GarageHUDKit/
│   │   ├── Models/           ← Vehicle, Part, PerformanceRecord, telemetry, knowledge states
│   │   ├── Persistence/      ← GarageStore (source of truth), CloudKit sync, image store
│   │   ├── Steward/          ← reasoning engine: rules, bands, context, fleet, briefing
│   │   ├── StewardVoice/     ← speech in/out, conversation core, driving-mode policy
│   │   ├── Live/             ← OBD-II PID decoder, ELM327 handshake, BLE transport
│   │   ├── Views/            ← SwiftUI screens
│   │   └── DesignSystem/     ← HUD visual primitives
│   └── Tests/GarageHUDKitTests/
└── GarageHUD-iOS/            ← thin Xcode app shell (iOS + macOS), compiles the kit's sources
```

The **package is the product**; `GarageHUD-iOS` is a thin shell that compiles `GarageHUDKit`'s
sources directly and adds entitlements, Info.plist usage strings, and app icon.

## Build & test

**Package (logic + reasoning), from `GarageHUDKit/`:**

```sh
swift build       # compiles clean under -strict-concurrency=complete
swift test        # 465 tests: reasoning rules, telemetry decoding, handshake + transcript replay,
                  # briefing, stream lifecycle, envelope/knowledge honesty, injected-clock determinism
```

CI (`.github/workflows/ci.yml`) runs the package tests and an iOS-simulator app build on every
push and PR.

**The app (macOS or iOS simulator):**

```sh
xcodebuild -project GarageHUD-iOS/GarageHUD.xcodeproj -scheme GarageHUD \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# or: -destination 'platform=macOS'
```

Requires Xcode 26.x (iOS 26 / macOS 14 SDK). CloudKit sync and the paid 8-bay unlock require a
paid Apple Developer team; sideloading for personal use works without one.

## What Fleet Steward does

The reasoning core (`Steward/`) reads the recorded model and emits `StewardObservation`s, each
carrying its **evidence**, an honest **evidence band** (`CONFIRMED / STRONG / MODERATE / WEAK /
INSUFFICIENT` — never a fabricated percentage), a **tone**, and a **provenance**. It reasons at
three levels, all through one core:

- **Per vehicle** — support gaps (fueling/cooling/brakes), build freshness, cost-to-power
  (labeled approximate: measured wheel vs factory crank), and timeline-aware rules (install
  ordering, stale tune, dyno plateau).
- **Live** — over an OBD-II frame, against the vehicle's own `OperatingEnvelope`; only *fresh*,
  *measured* values earn measured provenance.
- **Fleet** — value leader, neglected car, confirmed shared gaps.

It surfaces in the dashboard, an **Ask Steward** conversation (typed or spoken), a **garage
briefing**, and the **live session**.

### Design principles that shaped the code

- **Not-logged ≠ not-installed.** `ComponentKnowledge` distinguishes confirmed-present,
  confirmed-absent, undocumented, and unknown; an undocumented subsystem is never reported as a
  missing one, and empty/imported records are never warned at. (ADR-0003)
- **Honest telemetry.** Every live value is independently timestamped and sourced; stale values
  go *unavailable*, never frozen; a frame is never "measured" as a whole. (ADR-0004)
- **Pure and deterministic.** Rules are functions of `(model, StewardContext)` — no `Date.now`
  reached for inside — with stable observation identities and total ordering.

## Documentation

| Doc | What it covers |
|-----|----------------|
| [CONSTITUTION.md](docs/CONSTITUTION.md) | Mission, North Star, Steward doctrine, roles |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Boundaries, source of truth, reasoning + telemetry model |
| [PERSISTENCE.md](docs/PERSISTENCE.md) | Storage, CloudKit sync, schema-migration strategy |
| [adr/](docs/adr/) | Decision records (whole-doc sync, voice, evidence bands, telemetry honesty) |
| [TECH_DEBT.md](docs/TECH_DEBT.md) · [DESIGN_DEBT.md](docs/DESIGN_DEBT.md) · [FUTURE.md](docs/FUTURE.md) | Known debt and the parking lot |

## Status & known gaps

Actively developed. The reasoning, persistence, and telemetry logic is unit-tested, and the
Veepeak OBDCheck BLE path is now field-validated on Tim's iPhone and vehicle:

- **OBD-II** — two independent sessions discovered the adapter, opened its FFF0/FFF1/FFF2 serial
  channel, verified ELM, received a supported `41 00` vehicle response, and decoded measured data
  in 2.4 and 2.7 seconds. A genuine mid-session disconnect/reconnect and multi-ECU/ISO-TP vehicle
  remain unverified (TECH_DEBT TD-004).
- **Voice / conversational Steward** — pure behavior is tested, but cloud voice with a real key,
  speech-in against a real microphone, and the Apple-Intelligence LLM path still need on-device
  validation (TECH_DEBT TD-007).
- **Cloud sync** — conservative snapshots, append preservation, and deletion tombstones are
  tested. Scalar, part, and maintenance edit races remain whole-document last-writer-wins pending
  per-record history (TECH_DEBT TD-001).
