# ADR-0001: Keep Whole-Document Sync for Now, Add Conservative Conflict Protection

## Status

Accepted

## Context

GarageHUD currently stores the entire garage graph as local JSON and syncs that graph to one CloudKit garage record. This is simple and appropriate for an early personal app with a small number of vehicles and devices.

The risk is concurrent editing: if Mac and iPhone both edit before syncing, a delayed push can overwrite newer cloud data.

## Decision

Keep whole-document sync for now, but make pushes conservative:

- Before pushing, check whether CloudKit has a newer version than this device last applied.
- If so, do not overwrite cloud.
- Save the attempted local snapshot into `Conflict Snapshots/`.
- Apply the newer cloud garage locally.
- Surface `.conflict(URL)` in sync status.

## Consequences

Benefits:

- Prevents the worst failure mode: silent cloud overwrite.
- Preserves local attempted edits for manual recovery.
- Avoids premature event-sync architecture.

Costs:

- Does not automatically merge concurrent edits.
- Requires future UI to expose and resolve conflict snapshots elegantly.

## Future Direction

When vehicle memory becomes more event-centric, move selected data types to per-event CloudKit records or operation-based sync.
