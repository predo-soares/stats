 # S9 — Reconcile and promote Experimental providers

## What to build

Individually reconcile Experimental Grok, Z.ai, and Antigravity adapters when a user-authorized real source becomes available. Promotion is per provider and never implied by fixture success.

## Acceptance criteria

- [ ] Each reconciled provider has a redacted evidence record comparing source and app results.
- [ ] A discrepancy leaves only that provider Experimental and documented.
- [ ] Supported promotion preserves the adapter's privacy and coverage behavior.

## Blocked by

- S6 — Track xAI Grok local activity as Experimental.
- S7 — Track Z.ai usage as Experimental.
- S8 — Track Antigravity local activity as Experimental.

## Implementation notes

### Status: blocked (all three providers)

No user-authorized real sources were available in this session for Grok, Z.ai, or Antigravity. Fixture success from S6–S8 does **not** promote any provider. All three remain **Experimental**. No validation was fabricated.

| Provider | Experimental commit family | Real-source access | Result |
|---|---|---|---|
| Grok | `4483c33` | Not available | Stays Experimental |
| Z.ai | `e256a67` | Not available (no paid/API account) | Stays Experimental |
| Antigravity | `3c60e5b` | Not available | Stays Experimental |

### Verification
- No redacted real-source evidence records collected.
- Support states unchanged: Grok / Z.ai / Antigravity → Experimental.
- No code promotion path exercised.

### Commit
Documentation-only record of the blocker (this file). Commit `222fa96`.

## Cursor delegation prompt

Handle local slice S9 one provider at a time when a user-authorized real source is available. Reconcile Grok, Z.ai, and Antigravity with redacted evidence; promote only matching providers and document every discrepancy. Do not fabricate account validation. Update this document with evidence and verification; commit only necessary code changes once.
