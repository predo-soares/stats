 # S5 — Reconcile Pi against a representative local session

## What to build

Reconcile the Experimental Pi adapter with a user-authorized representative local Pi session and only promote it when token totals and provenance are confirmed.

## Acceptance criteria

- [ ] A redacted report compares the local Pi session and app projection.
- [ ] Duplicate-accounting assumptions are tested; ambiguity keeps Pi Experimental.
- [ ] Supported promotion occurs only after successful reconciliation.

## Blocked by

- S4 — Track Pi local runtime activity as Experimental.

## Implementation notes

### Status: blocked

No representative user-authorized local Pi session was available for reconciliation in this session. Pi remains **Experimental**. Duplicate-accounting assumptions were not promoted; fixture isolation (S4) only proves ledger partitioning, not cross-source identity.

### Verification
- No real-session evidence collected.
- Pi support state remains Experimental after S4 (`f0b1e89` family).

### Commit
Documentation-only record of the blocker (this file).

## Cursor delegation prompt

Handle local slice S5 against a representative local Pi session. Compare redacted source metadata with the app projection, test duplicate-accounting assumptions, and promote only when confirmed. If no suitable session exists, document the blocker instead of fabricating success. Update this document with evidence and verification; commit only necessary code changes once.
