 # S7 — Track Z.ai usage as Experimental

## What to build

Deliver an Experimental Z.ai provider path using an explicit user-owned credential only where the source requires it. Cover fixture-based retrieval, redacted accounting, provider detail disclosure, state UI, and incomplete-cost behavior.

## Acceptance criteria

- [x] Z.ai enrollment explains any explicit credential requirement before connection.
- [x] Credentials remain in Keychain and outside the ledger, logs, diagnostics, and exports.
- [x] Sanitized fixtures verify independent tokens, incomplete pricing, failure preservation, and source evidence.
- [x] Experimental indicator/tooltip and native UI behavior pass checks.

## Blocked by

- S1 — Enroll providers with visual support states.

## Implementation notes

### Implemented
- `UsageProviderIdentity.zai` (Experimental) with Keychain-only credential disclosure in Settings.
- `ZaiCredentialVault` (service `aestech.stats.zai`) — never writes keys into ledger/events.
- `ZaiUsageImporter` parses sanitized model rollups from `zai-usage.fixture.json`; import refuses without credential presence.
- Shared `local_usage_events` + dashboard card / customization when enrolled.
- `scripts/run_zai_usage_self_checks.swift` (1_850_000 tokens / 2 model rows; incomplete pricing; no credential leak).

### Decisions
- Fixture/API import gated on Keychain presence only; credential material is never attached to `LocalUsageEvent`.
- Remains Experimental; no live paid-account reconciliation in this slice.

### Verification
- Z.ai self-check PASS; native `xcodebuild` Debug build SUCCEEDED (`.build-run`).

### Limitations
- Without a real API fetch path, import reads the sanitized fixture/bundle when a credential is present.
- Pricing stays incomplete until catalog rates exist for GLM models.

### Commit
`66289f9`

## Cursor delegation prompt

Implement local slice S7 as an Experimental Z.ai path. Keep any explicit user credential in Keychain only, never in logs, diagnostics, or the ledger. Use sanitized fixtures to verify accounting, incomplete pricing, failures, source evidence, and tooltip state. You may spawn independent fixture/test subagents, but own integration; update this document, run verification, and create one focused commit.
