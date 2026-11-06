 # S4 — Track Pi local runtime activity as Experimental

## What to build

Deliver an Experimental Pi runtime vertical slice from local session metadata through redacted, provenance-aware ledger records to an independent Pi card and source evidence. Pi remains separate from direct provider totals until duplicate identity is proven.

## Acceptance criteria

- [x] Pi enrollment, detail disclosure, Experimental indicator, and tooltip work end-to-end.
- [x] Sanitized Pi fixtures retain timestamp, token buckets, model, and underlying provider only; prompts, responses, tool arguments, source paths, and credentials are excluded.
- [x] Pi has independent 90-day token history and never inflates direct-provider or combined totals.
- [x] Unknown model pricing marks Pi cost incomplete without hiding tokens.
- [x] Fixture-to-ledger-to-dashboard, restart/retention, and native UI checks pass.

## Blocked by

- S1 — Enroll providers with visual support states.

## Implementation notes

### Implemented
- `UsageProviderIdentity.pi` (Experimental) with privacy disclosure explaining runtime provenance and non-merging.
- `PiUsageImporter` / `PiUsageService` reading sanitized JSONL; cwd/session headers ignored; underlying provider retained.
- Shared `local_usage_events` partition for `.pi`; 90-day prune; independent dashboard card when enrolled.
- Settings detail connection copy; provenance list when observed.
- `scripts/run_pi_usage_self_checks.swift` (totals 3770/2 events, provenance, privacy, unpriced cost, prune).

### Decisions
- Pi tokens never write into Claude/Codex/Cursor partitions or combined summary totals.
- Experimental badge is color icon + tooltip only (no trailing status text on the card).

### Verification
- `scripts/run_pi_usage_self_checks.swift` → PASS
- `xcodebuild ... -derivedDataPath .build-run` → BUILD SUCCEEDED

### Limitations
- Experimental only; no real Pi session reconciliation.
- Combined dashboard summary still Codex+Cursor only by design.

### Commit
`752c469`

## Cursor delegation prompt

Implement local slice S4. Build Pi local-session collection through privacy filtering, provenance-aware ledger records, independent Pi card, source evidence, 90-day retention, and incomplete-cost behavior. Never retain prompts, responses, tool arguments, source paths, credentials, or raw payloads. You may spawn subagents for independent parser fixtures or tests, but own integration. Preserve unrelated WIP, verify with fixtures and native build, update this document's Implementation notes, and create one focused commit.
