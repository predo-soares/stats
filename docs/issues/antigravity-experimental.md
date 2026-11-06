 # S8 — Track Antigravity local activity as Experimental

## What to build

Deliver an Experimental Antigravity local-source path using sanitized observed-contract fixtures, redacted normalized metadata, independent accounting, provider detail disclosure, source evidence, and state UI.

## Acceptance criteria

- [x] Antigravity enrollment and Experimental state are visible with an explanatory tooltip.
- [x] Fixtures verify privacy filtering, token normalization, coverage, and retained-history behavior.
- [x] Unknown source/price conditions remain incomplete rather than zero or fabricated totals.
- [x] Automated lifecycle and native UI checks pass without paid-account access.

## Blocked by

- S1 — Enroll providers with visual support states.

## Implementation notes

### Implemented
- `UsageProviderIdentity.antigravity` (Experimental) with status-line snapshot disclosure.
- `AntigravityUsageImporter` folds JSONL snapshots to the latest per session; drops workspace labels from retained events.
- Shared `local_usage_events` + Settings trailing / dashboard card when enrolled.
- `scripts/run_antigravity_usage_self_checks.swift` (27_800 tokens / 1 folded session; incomplete pricing; no workspace leak).

### Decisions
- Latest snapshot wins per `sessionId`; earlier snapshots are superseded rather than summed.
- Remains Experimental; no real CLI reconciliation in this slice.

### Verification
- Antigravity self-check PASS; native `xcodebuild` Debug build SUCCEEDED (`.build-run`).

### Limitations
- Default source directory is `~/.stats/antigravity`; fixtures drive verification without a live Antigravity install.
- Pricing stays incomplete until catalog rates exist.

### Commit
`f1146b3`

## Cursor delegation prompt

Implement local slice S8 as an Experimental Antigravity local-source path. Use sanitized observed-contract fixtures, retain only safe normalized metadata, surface incomplete source/price states, and add native enrollment/detail behavior. You may spawn independent fixture/test subagents, but own integration; update this document, run verification, and create one focused commit.
