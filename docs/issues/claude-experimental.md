 # S2 — Track Claude local activity as Experimental

## What to build

Deliver an Experimental Claude provider vertical slice: sanitized observed-contract fixtures flow through local discovery, redacted normalization, durable ledger records, independent dashboard presentation, source evidence, and provider detail settings. Do not claim real-account reconciliation.

## Acceptance criteria

- [ ] Claude is enrolled and displayed as Experimental with a tooltip.
- [ ] Sanitized fixtures produce correct independent token totals, coverage, and source evidence without retaining private session content.
- [ ] Unknown model rates preserve tokens and make Claude estimated cost incomplete.
- [ ] Claude failure/unavailability preserves known data and does not block other providers.
- [ ] Fixture-to-ledger-to-dashboard and native UI checks pass.

## Blocked by

- S1 — Enroll providers with visual support states.

## Implementation notes

### Implemented
- `UsageProviderIdentity.claude` with Experimental support state, privacy disclosure, and SF Symbol logo fallback.
- `LocalProviderUsageModels`, `ClaudeUsageImporter`, `local_usage_events` ledger APIs, and `ClaudeUsageService` with preserve-on-failure refresh.
- `UsageStore` wiring (`claudeConnectionEnabled`, independent refresh, source evidence, models/trend/cost hooks).
- Dashboard Claude card via `ProviderCardPresentationFactory.claude`, Settings connection copy for `~/.claude/projects` read-only access.
- `scripts/run_claude_usage_self_checks.swift` for fixture math, privacy shape, unpriced cost, and failure isolation.

### Verification
- `scripts/run_claude_usage_self_checks.swift` → PASS (fixture totals 15634 tokens / 3 events, privacy shape, unpriced cost, preserve-on-failure).
- `xcodebuild -project stats.xcodeproj -scheme stats -configuration Debug build -derivedDataPath .build-run` → BUILD SUCCEEDED.

### Limitations
- Experimental only: no Claude account or quota reconciliation.
- Parser follows sanitized JSONL contract; real on-disk layout may differ.
- Combined summary/cost comparisons intentionally omit Claude until coverage rules are extended.

### Decisions
- Shared `local_usage_events` ledger table for Experimental local adapters.
- Missing `~/.claude/projects` preserves prior ledger rows and marks coverage unavailable.

### Commit
`677eea2`

## Cursor delegation prompt

Implement local slice S2. Build the complete fixture-driven Experimental Claude path from observed local source contract through privacy filtering, ledger, source evidence, cost state, and independent provider card. Use no paid account and do not claim Supported. You may spawn subagents for independent fixture or test work, but own integration. Preserve unrelated WIP, run focused checks and the native build, update this document's Implementation notes, and create one focused commit for S2.
