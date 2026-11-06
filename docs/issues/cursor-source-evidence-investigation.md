# Cursor source evidence and incomplete history

Status: active investigation. This issue blocks representing Cursor token totals as complete account activity and blocks combined Cursor + Codex totals.

## Problem

The app connects to the current Cursor account and the Cursor dashboard usage-events endpoint returns valid, timestamped token events. However, the account owner is actively using Cursor in November 2026 while the newest returned event is from 13 October 2026.

The app must not display that retained October subtotal as current-period Cursor consumption or silently include it in combined consumption.

## Confirmed evidence

Redacted diagnostic exported on 2026-11-05:

- Connected account fingerprint: `user_01M…H0W4` (the current GitHub Cursor identity).
- Today request: 2026-11-05 00:00 local through the diagnostic cutoff; 0 retained events and 0 tokens.
- Last 7 Days request: 2026-10-30 00:00 local through the diagnostic cutoff; 0 retained events and 0 tokens.
- Last 30 Days request: 2026-10-07 00:00 local through the diagnostic cutoff; 1,776 retained events and 126,291,373 tokens.
- Earliest retained Last 30 Days event: 2026-10-10 18:20:22 UTC.
- Latest retained Last 30 Days event: 2026-10-13 21:31:09 UTC.
- The retired business-related Google Cursor identity is present only as historical local metadata and cannot be queried; it is not the connected app identity.

## Root causes identified

### Source coverage is stale

The endpoint request covers the current period, but returned timestamped events stop weeks before its requested cutoff. A successful HTTP request or decoded response is not evidence of complete account history.

### Import checkpoints are not canonical

Each refresh seeds a new 30-day range ending at the exact current time. The diagnostic showed 18 overlapping ranges, all marked `completed`. Event identity de-duplication prevents inflated token totals, but these checkpoints make coverage appear healthier than it is and create needless request history.

## Product decision

Until a source can demonstrate current timestamped Cursor token events:

- Preserve known Cursor token subtotals, but label the history incomplete.
- Do not show Cursor token values as complete current-period totals.
- Do not include incomplete Cursor token history in combined consumption or comparisons.
- Continue independent Cursor quota collection and presentation.

## Required implementation

1. Add a direct, redacted Today probe before ledger reporting. It records only the requested window, outcome, event count, token subtotal, earliest/latest event timestamp, and a safe failure reason.
2. Use canonical hourly import cutoffs so repeated refreshes do not produce overlapping 30-day checkpoints.
3. Treat a response whose latest event materially precedes the requested cutoff as incomplete history. Never infer missing time is zero activity.
4. Surface the probe, retained-window summaries, and import state in Settings → Diagnostics → Cursor Source Evidence. Exported JSON must exclude credentials, raw payloads, prompts, event IDs, and source code.
5. Add deterministic fixture checks for an empty current-day response, stale latest event, overlapping checkpoint prevention, and a failing request.

## Acceptance criteria

- [ ] A source-evidence report distinguishes a current empty response, stale returned events, an unavailable response, and local retained data.
- [ ] Repeated refreshes within one hour reuse the same import windows rather than creating overlapping checkpoint rows.
- [ ] Today, Last 7 Days, and Last 30 Days show `History incomplete` when retained Cursor events lag the request cutoff.
- [ ] Incomplete Cursor history is excluded from combined token/cost comparisons while quota remains available.
- [ ] Redacted export contains only safe metadata and passes a review confirming it has no credentials or raw payload content.
- [ ] Fixture-driven checks reproduce the observed October-only response and verify no misleading complete total is published.

## Non-goals

- Recovering the retired business Cursor account.
- Reading Cursor browser cookies, decrypting Cursor.app tokens, or importing private local application secrets.
- Treating quota usage as a substitute for token consumption.
