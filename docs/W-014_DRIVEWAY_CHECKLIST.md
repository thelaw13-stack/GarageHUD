# W-014 — OBD hardware validation: driveway checklist

Turns the largest unproven mass of code (the Live/OBD stack) from faith into findings in one
session. Adapter: **Veepeak OBDCheck BLE** (Bluetooth-LE, recognized by the app's catalog). Tim runs
the physical steps; Vector diagnoses from the artifacts captured at the end.

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

## Step 4 — Multi-ECU / ISO-TP (criterion 2, automatic)
Nothing to do by hand — if the car answers multi-frame, the decoder handles it. It's captured in the
Connection Report (Step 6). Trucks/newer cars (Tundra) are the most likely to exercise this.

## Step 5 — Reconnect (criterion 3: survive a disconnect/reconnect)
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
