 # S3 — Reconcile Claude against a real account

## What to build

Reconcile the Experimental Claude adapter against a real, user-authorized source. Promote it to Supported only if the observed totals, coverage, and privacy boundary match the adapter contract.

## Acceptance criteria

- [ ] A redacted evidence record compares representative real Claude activity with the app projection.
- [ ] Any source discrepancy remains visible and Claude stays Experimental.
- [ ] Only a successful reconciliation promotes Claude to Supported.

## Blocked by

- S2 — Track Claude local activity as Experimental.

## Implementation notes

### Status: blocked

No user-authorized real Claude source or paid-account access is available in this session. Claude remains **Experimental**. No promotion to Supported was performed, and no validation was fabricated.

### Verification
- Confirmed Experimental path from S2 (`50573ea` family) remains the active support state.
- No real-source evidence record collected.

### Commit
Documentation-only record of the blocker (this file).

## Cursor delegation prompt

Handle local slice S3 only when a user-authorized real Claude source is available. Reconcile the Experimental adapter using redacted evidence, promote it only if totals and coverage match, otherwise document the discrepancy and keep Experimental. Do not invent validation. Update this document with the evidence and verification; if code changes are required, create one focused commit.
