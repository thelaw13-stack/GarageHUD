# W-014 — OBD hardware validation: driveway checklist

Turns the largest unproven mass of code (the Live/OBD stack) from faith into findings in one
session. Adapter: **Veepeak OBDCheck BLE** (Bluetooth-LE, recognized by the app's catalog). Tim runs
the physical steps; Vector diagnoses from the artifacts captured at the end.

## Which cars (and which not)
Candidates: **Fozzy** (boosted — exercises the baro-corrected boost path), **Tundra** (newest — most
likely to answer multi-ECU/ISO-TP), **S2K**. **Not the Baja** — it's a pre-1996 air-cooled VW with no
OBD-II port; the app now says so on its Live tab (there's nothing to plug into).

## Pre-flight (60 seconds)
- Plug the Veepeak into the car's OBD-II port (under the dash, driver's side).
- **Ignition to RUN, or engine running.** Live PIDs need the ECU awake. Engine running is best.
- **Close every other OBD app** (Torque, Car Scanner, OBD Fusion, the Veepeak app). Two apps can't
  hold one adapter — this is the #1 cause of "it won't connect."
- iPhone Bluetooth ON. **Do NOT pair the Veepeak in iOS Settings** — connect *inside GarageHUD only*.

## Step 1 — Pair (criterion: connect to a real ELM327)
1. Open GarageHUD → tap a car → **Live** tab.
2. Feed selector: **OBD-II Adapter**.
3. Adapter model dropdown: **Veepeak OBDCheck BLE**.
4. Tap **Start / Scan**. Approve the iOS Bluetooth prompt if one appears.
5. The Veepeak should appear under **Discovered Adapters** (name + RSSI). Tap it.
6. Watch the connection rail climb: Scanning → Opening link → Pairing → **Linked · Measuring**.

✅ Pass = the rail reaches "Linked · Measuring" and the gauges light up.

## Step 2 — Decode + sanity-check (criterion: decode live PIDs)
With the engine running, the gauges should read plausibly:
- RPM ≈ 600–900 at idle; rises when you blip the throttle.
- Coolant climbs toward ~180–210°F as it warms.
- Throttle ≈ 0% at rest → moves with the pedal.
- Boost ≈ 0 psi at idle **(now baro-corrected — Dad's C3 fix; watch this on the S2K/Fozzy)**.

⚠️ Any implausible value (boost reading high at idle, coolant pinned, RPM frozen) **is a finding** —
note it.

## Step 3 — Pull detection (bonus, only if safe & legal)
On a private driveway/road, one wide-open-throttle pull. Pull Guardian should detect it and grade
what it actually measured vs estimated. Skip if not safe — not required for W-014.

## Step 4 — Multi-ECU / ISO-TP (criterion 2) — ⚠️ NOT CURRENTLY MEASURABLE
**This step is on hold. Do not spend a session on it yet.**

This previously said multi-ECU was captured automatically in the Connection Report. That was wrong:
nothing in the app records a negotiated protocol number, responder count, or multi-frame assembly —
the journal holds only stage and message strings. A run on a multi-ECU car produces a report
identical to a single-ECU one, so the criterion comes back *unmeasured* rather than passed or
failed. Tim spent a Tundra session on 2026-07-20 discovering exactly that.

`W-069` instruments the report first, passively, from traffic the handshake already produces. Once
that lands, this step becomes worth doing — on the Tundra, still the fleet's best candidate.

## Step 5 — Reconnect (criterion 3) — ✅ PASSED 2026-07-20
Kept for future regression runs. Tim unplugged the adapter mid-session and replugged it: the rail
went DEGRADED → RETRYING (1 of 5) → SCANNING → FOUND (-37 dBm) → full re-handshake → MEASURING,
11.3s from drop to live data on the first retry. Walking away far enough to drop the link proved
impractical; unplugging is the harsher test anyway, since it cuts adapter power rather than just the
radio link.

Original instructions:
While a session is live, do ONE of:
- Walk ~30 ft away until it drops, then walk back, **or**
- Unplug the adapter for 5 seconds and replug it.

✅ Pass = GarageHUD reconnects on its own (rail shows Degraded → Reconnecting → Measuring).

## Step 6 — Capture for Vector (the whole point)
1. **Connection Report** — Live tab → **Last Connection Report** → **Share Connection Report** →
   save to Files or send it to Tim's Mac. This is the primary diagnostic (handshake stages, services,
   channels, protocol).
2. **Screenshots**: the live gauges lit up, and the Discovered Adapters list.
3. One line on anything that felt off (delays, drops, weird numbers).

Hand those to Vector. Each becomes a finding: confirmed, fixed, locked with a test — same as the
honesty audit.

## If it stalls — quick decoder
- Stuck at **Scanning**: adapter not seen. Another app holds it, it's unpowered (ignition off), or
  it's not a BLE unit. Power-cycle the adapter, confirm ignition RUN.
- Reaches **Pairing** then fails: characteristic/notify issue — share the Connection Report, that's
  exactly the case it exists for.
- **Linked but no data / gauges dark**: connected but the ECU isn't answering the PIDs (protocol or
  engine-off). Confirm engine running; share the report so the protocol layout can be added.
