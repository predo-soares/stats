 # S6 — Track xAI Grok local activity as Experimental

## What to build

Deliver an Experimental xAI Grok provider path using sanitized observed-contract fixtures, redacted local metadata, independent accounting, provider detail disclosure, source evidence, and state UI.

## Acceptance criteria

- [x] Grok can be enrolled, is visibly Experimental, and its tooltip explains the state.
- [x] Fixtures verify correct token normalization, privacy filtering, and independent ledger/dashboard publication.
- [x] Unknown pricing stays incomplete; provider failures do not erase known data or block other sources.
- [x] Automated lifecycle and native UI checks pass.

## Blocked by

- S1 — Enroll providers with visual support states.

## Implementation notes

### Implemented
- `UsageProviderIdentity.grok` (Experimental) with local-session disclosure.
- `GrokUsageImporter` preferring transcript rows over signals for the same session; signals fill gaps.
- Shared `local_usage_events` + `ExperimentalLocalUsageService`; Settings/dashboard card when enrolled.
- `scripts/run_grok_usage_self_checks.swift` (6350 tokens / 2 events after preference).

### Verification
- Grok self-check PASS; native build SUCCEEDED.

### Limitations
- Experimental only; signals attribute rollups to the input bucket when category splits are absent.

### Commit
`b84737d`

## Cursor delegation prompt

Implement local slice S6 as an Experimental xAI Grok path using sanitized observed-contract fixtures. Cover enrollment, privacy filtering, independent ledger/dashboard state, source evidence, unknown pricing, and failure preservation. Do not use or claim a paid account. You may spawn independent fixture/test subagents, but own integration; update this document, run verification, and create one focused commit.
