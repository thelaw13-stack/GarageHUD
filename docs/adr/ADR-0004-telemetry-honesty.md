# ADR-0004: Per-Metric Telemetry Honesty and a Response-Driven OBD Transport

## Status

Accepted

## Context

The first OBD-II implementation had three trust-breaking defects:

1. It initialized telemetry with defaults (coolant 175°F, boost 0, …) and emitted a complete
   frame each cycle regardless of whether every PID actually answered. A frame could mix a real
   RPM with a stale coolant and a default throttle — and then be labeled "measured" with raised
   confidence purely because the *transport* was Bluetooth.
2. The ELM327 bring-up pipelined `ATZ/ATE0/…` and declared success immediately, with no
   acknowledgement, timeout, retry, or verification — wrong for a command-response serial clone.
3. `stop()` called `continuation.finish()`, permanently ending the stream; a restarted source
   could reconnect but never deliver frames again.

This violated the project's central promise: history and evidence must be more trustworthy than
presentation.

## Decision

**Per-metric provenance and freshness.** Each value is a `TimedMeasurement { value, receivedAt,
source }`. A `LiveTelemetryFrame` holds five independently timestamped/sourced metrics plus the
`OBDConnectionState`. Consumers judge freshness per metric against `LiveFreshness.window`; a PID
that stops answering goes **unavailable** (nil) downstream, never frozen at its last value.
Reasoning tags a value `.measuredLive` (and grades it higher) only when *that value* was decoded
from the adapter this instant — never the whole frame.

**Response-driven handshake.** `ELM327Handshake` is a pure state machine: exactly one command in
flight, advanced only on a prompt-terminated reply or a controlled timeout, with retries and a
failure cap. The transport (`OBDLiveDataSource`) drives it and then round-robins PIDs through the
pure `OBDPIDDecoder`, one request at a time.

**Reusable lifecycle.** `stop()` halts transport and polling but leaves the stream open; the
stream is finished exactly once, in `deinit`. The same source can be restarted.

**Vehicle-specific envelopes.** `OperatingEnvelope` gives each car its own coolant limits and a
boost signal that only exists for forced-induction cars; boost is judged only under throttle.

## Consequences

Benefits:

- "Measured" means measured. Stale/default/missing values never masquerade as live truth.
- The handshake and decoder are unit-tested (state transitions, ELM327 quirks, freshness,
  lifecycle) without hardware.
- Live thresholds mean something per vehicle instead of firing generically.

Costs / outstanding:

- The BLE transport compiles and follows the standard flow but is **unproven against physical
  hardware**. Real-adapter validation, ISO-TP/multi-ECU handling, and serial-transcript replay
  remain (TECH_DEBT).
- Adapter **pairing**: validated adapter profile, user device selection, and ELM327 identity
  verification are not yet implemented — auto-connect currently trusts service-UUID discovery.
