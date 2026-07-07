# Technical Debt Register

## TD-001 — Whole-document CloudKit sync

Priority: High

Current state: The entire garage graph is synced as one JSON blob.

Risk: Concurrent edits from multiple devices cannot be merged semantically. A conservative conflict guard now prevents silent overwrites, but true merging is deferred.

Near-term decision: Accept whole-document sync while preserving conflict snapshots.

Long-term direction: Move toward event-based records or operation-based sync once vehicle history grows.

## TD-002 — Test coverage just started

Priority: High

Current state: A test target now exists with initial model tests.

Risk: Parser, advisor, persistence, and sync behavior can regress silently without coverage.

Next steps: Add tests for build sheet parsing, vehicle cost calculations, live record capture, and conflict snapshot encoding.

## TD-003 — Steward vocabulary exists conceptually, not in code

Priority: Medium

Current state: `BuildAdvisor` and `PurchaseManager` are early seeds of Steward-like behavior.

Risk: One-off managers could proliferate without a coherent Steward service boundary.

Next steps: Do not refactor prematurely. Watch for the third advisor-like service; that is likely the threshold for introducing a `Steward` namespace/boundary.
