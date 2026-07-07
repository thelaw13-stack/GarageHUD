# GarageHUD Architecture

## Current Shape

GarageHUDKit is the product core. App shells should be thin wrappers around this package.

Current high-level boundaries:

- `Models/` — vehicle data, parts, events, notes, photos, live telemetry samples.
- `Persistence/` — local JSON persistence, CloudKit sync, image storage, purchase state, parser/advisor logic.
- `Views/` — SwiftUI presentation.
- `DesignSystem/` — visual primitives and HUD styling.

## Source of Truth

`GarageStore` is the application source of truth for garage data. Views bind into `GarageStore.vehicles`; persistence and sync should remain behind the store.

## Sync Model

The current CloudKit implementation stores the garage graph as a whole-document JSON payload on one private CloudKit record, with photos stored as separate records.

This is acceptable for the current stage because it keeps the merge model simple. It is not the final architecture for high-volume, multi-device editing.

The near-term rule is conservative whole-document sync:

- Never silently overwrite a newer cloud garage with a stale delayed local push.
- Preserve attempted local changes as conflict snapshots when necessary.
- Prefer visible conflict over invisible data loss.

## Future Direction

GarageHUD should gradually move toward event-centric vehicle memory. This does not require a rewrite today. It does require avoiding model decisions that make history impossible later.

Future Steward capabilities should reason over:

- Vehicle memory
- Fleet memory
- Provenance
- Confidence
- Context
- Owner goals

Steward should not own truth. GarageHUD owns memory; Steward interprets it.

## Voice Direction

Voice is a first-class future subsystem for active vehicle use and garage work.

Proposed future boundary:

```text
StewardVoice/
├── SpeechInput
├── IntentParser
├── CommandRouter
├── VoiceResponse
└── DrivingModePolicy
```

The most important component is `DrivingModePolicy`: answers must become shorter, safer, and less visually demanding while the vehicle is active.
