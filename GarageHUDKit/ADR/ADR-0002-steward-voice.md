# ADR-0002: Voice Is a First-Class Steward Interface

## Status

Accepted

## Context

GarageHUD will be used while driving, while working under or around a vehicle, and while the user's hands and eyes are occupied. Typing is not acceptable in those contexts.

## Decision

Voice is a required future capability, not a novelty feature.

The design must support:

- Quick status queries
- Live logging commands
- Maintenance capture
- Garage work assistance
- Short driving-mode responses
- Longer parked-mode explanations

## Consequences

Voice requires a policy layer, not just speech recognition. The same question may need different answers depending on whether the car is parked, moving, being worked on, or being reviewed later.

Proposed future subsystem:

```text
StewardVoice/
├── SpeechInput
├── IntentParser
├── CommandRouter
├── VoiceResponse
└── DrivingModePolicy
```
