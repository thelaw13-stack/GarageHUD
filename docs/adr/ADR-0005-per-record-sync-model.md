# ADR-0005: Per-Record Stamps and Coherence Groups for Concurrent Edits

## Status

**Accepted** — 2026-07-19, by Tim, as written (coherence grouping unamended). Implementation is
tracked as `W-064`. [ADR-0001](ADR-0001-whole-document-sync.md) remains in force for everything this
does not cover: the vehicle set, append-only records, and the conflict-snapshot guard.

## Context

The whole-document bridge is now as conservative as it can honestly get:

- Conflict snapshots and never-applied-state protection prevent silent whole-document loss.
- **W-054** preserves append-only records (pull reports, performance records, build events, notes,
  photos) across document adoption, so a driveway pull survives a Mac push.
- **W-056** tombstones (`Vehicle.deletedRecordIDs`) close the deletion half, so a delete propagates
  instead of being resurrected by the other device's held copy.

What remains is stated plainly in `GarageMerge`: **scalars, parts, and maintenance are still
adopt-side-wins.** Those are the *edited* fields, and picking per-field winners without timestamps
would be, in that file's own words, "a guess wearing a merge's clothes."

Live telemetry made this urgent rather than theoretical. The phone now writes during driveway
sessions while the Mac holds spec edits — precisely the concurrent pattern last-writer-wins
punishes.

## The two traps this design exists to avoid

### Trap 1: device wall-clock time is not evidence

The obvious move is a `lastModified: Date` per field, newest wins. It is wrong here. Device clocks
skew, drift, and can be set by hand; a phone that is three minutes fast silently wins every race
against the Mac forever, and nothing in the record would show it. That is a truth claim GarageHUD
cannot support — the same standard the app already applies to a dyno figure or a stale telemetry
value applies to a merge decision.

The re-entry brief says this directly: do not guess winners from array order or device time.

### Trap 2: field-level merge can synthesize a state that never existed

This is the subtler one, and it is the same failure that produced W-061 today. There, every line of
the grounding record was individually true; the *adjacency* of two true facts is what lied.

Field-level last-writer-wins has exactly that shape. Take `factoryHorsepower` and
`factoryPowerBasis`. Edit the horsepower on the Mac as a crank figure; edit the basis on the phone
to wheel. Merge field-wise by newest and the result is a crank number labelled as a wheel figure —
a vehicle that never existed on either device, assembled from two individually-correct edits. Every
power derivation downstream then inherits it, and the evidence chip will call it Strong.

The same coupling exists for `purchasePrice` / `documentedTotalInvestment` (rule 4: purchase price,
build investment, and service spend never collapse into one number) and for
`serviceStatus.isInService` / its reason string.

A merge policy that can invent an incoherent car is not more honest than one that loses an edit. It
is less honest, because losing an edit is visible in a conflict snapshot and an invented state is
not visible at all.

## Decision

Three parts. Each is independently testable and lands in the stated order.

### 1. Hybrid logical clock stamps, not wall-clock timestamps

A stamp is `(physical: Date, counter: UInt64, node: UUID)`:

- `physical` is the device clock, but only ever used as a *floor* — never trusted alone.
- `counter` increments when two events share a physical millisecond, or when an incoming stamp is
  ahead of local time (the receiving device adopts the higher clock).
- `node` is a stable per-device id, used only as a deterministic final tiebreak.

This gives a total order that survives skew: a device with a fast clock cannot silently win forever,
because every peer adopts the observed maximum and advances past it. Comparison is pure and
therefore fully testable with an injected clock, matching the existing `now: Date = .now` pattern
used throughout `Live/`.

Stamps are **not** presented to the owner as times. They order events; they do not claim when
anything happened. `dateAdded` and record dates remain the human-facing truth.

### 2. Coherence groups, not free-floating fields

Fields are stamped in **groups that must move together**, not individually. A group is the unit of
merge. Proposed initial grouping:

| Group | Fields |
|---|---|
| `identity` | make, model, year, trim, nickname, colorName, garageSlot |
| `power` | factoryHorsepower, factoryTorque, factoryPowerBasis, drivetrain, engineDescription |
| `money` | purchasePrice, documentedTotalInvestment |
| `status` | serviceStatus (value and reason together) |
| `capability` | factoryForcedInductionOverride, obd2Override, operatingEnvelopeOverride |

Within a group the whole group wins or loses as a unit, so a merged vehicle is always a state that
genuinely existed on one device for that group. Cross-group mixing is safe *by construction*,
because the grouping is chosen so no derivation reads across two groups without the record's own
provenance.

This is the part that distinguishes the design from textbook field-level CRDT LWW, and it is the
part most likely to need revision once real conflicts are observed. The grouping above is a
starting hypothesis, not a proven partition.

### 3. Parts and maintenance become stamped records with tombstones

Each `Part` and `MaintenanceItem` carries its own stamp and participates in the existing tombstone
set. Concurrent edits to *different* parts then both survive — today one side's whole parts array
loses. Concurrent edits to the *same* part are ordered by stamp, and the loser is preserved in the
conflict snapshot exactly as today.

## Migration

Additive and legacy-tolerant, following the `GaragePersistence.Document` precedent:

- Absent stamps decode as a **zero stamp**, meaning "unknown and oldest."
- A stamped edit therefore beats an unstamped legacy value — the newer device's deliberate edit wins
  over a value nobody has touched since before the upgrade.
- **Two unstamped sides fall back to today's adopt-side-wins**, unchanged. No behavior regression for
  a garage that has not yet been written by a stamping client.
- Schema version increments; older clients hit the existing `.unsupportedVersion` refusal rather
  than silently dropping stamps they cannot represent. This matters: a client that round-trips a
  document while discarding stamps would resurrect the very races this removes.

## Test plan — written before the implementation

These are the tests that must exist and fail against today's code:

1. **Skew**: a device three minutes fast does not win indefinitely; peers adopt the higher clock and
   the next local edit orders after it.
2. **Tie**: identical physical time and counter resolve by node id, deterministically, same result
   on both devices.
3. **Coherence**: concurrent `factoryHorsepower` (Mac) and `factoryPowerBasis` (phone) edits never
   produce a crank figure labelled as wheel — the whole `power` group resolves to one device's state.
4. **Money coherence**: `purchasePrice` and `documentedTotalInvestment` cannot be merged from
   different devices into a combination neither owner entered.
5. **Independent parts**: edits to two different parts on two devices both survive.
6. **Same part**: concurrent edits to one part order deterministically, and the loser appears in the
   conflict snapshot.
7. **Legacy in**: an unstamped document merges exactly as today (adopt-side-wins), byte-identical
   result to the current implementation.
8. **Legacy out**: a stamped document survives a round-trip through the versioned envelope with
   stamps intact.
9. **Append records unaffected**: W-054 preservation and W-056 tombstone behavior are unchanged —
   the existing suites must stay green untouched.
10. **Determinism**: merging A into B and B into A yield the same result for every case above.

Test 10 is the one that would catch a subtly wrong design rather than a wrong implementation.

## Consequences

Benefits:

- Concurrent edits to different things stop being a coin flip.
- The winner is chosen by a defensible order rather than by whoever pushed last.
- A merged vehicle is always a state that existed, per coherence group.

Costs, stated honestly:

- Document size grows by one stamp per group and per part/maintenance item.
- The coherence grouping is a judgment call and will be wrong somewhere; it must be revisited the
  first time a real conflict produces a surprising result.
- This is still not full history. It orders edits; it does not let the owner see or replay them.
  Operation-based sync with a real log remains the long-term direction, and this design is a
  deliberate intermediate step chosen because it is testable and migratable in one increment.
- Stamps are metadata the owner cannot see. That is acceptable only because they never *assert*
  anything about the car; the moment a stamp is surfaced as "when this changed," it becomes a truth
  claim that needs the same evidence discipline as everything else.

## What this explicitly does not do

- It does not touch the OBD transport or the proven handshake.
- It does not change what the owner sees on any screen.
- It does not merge the vehicle SET (adding and removing whole cars stays adopt-side-wins).
- It does not resolve deletions made by clients too old to write tombstones. Only real history
  closes that, and it stays out of scope here.
