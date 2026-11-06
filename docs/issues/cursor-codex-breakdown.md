# Proposed implementation slices

Parent: [PRD #1](https://github.com/predo-soares/stats/issues/1)

Status: draft for user review. No implementation tickets have been published and no application implementation is authorized by this draft.

AFK means implementable and mergeable with automated, sanitized checks once dependencies are complete; it does not require logging into Pedro’s accounts during that slice. HITL marks the two explicit real-account/acceptance checkpoints. Propose ready-for-agent for AFK slices and ready-for-human for HITL slices.

Every slice includes a working path through collection/protocol, persistence/state, native presentation, and behavioral validation. Reuse existing layers where already provided; do not create separate storage-only or mock-UI-only tickets.

## Proposed order and dependencies

1. **S1 — Show persisted Codex token consumption for Today** · AFK · Blocked by: None · PRD stories: 1, 2, 3, 20, 32, 34, 35, 36, 55, 61, 62, 63, 66
2. **S2 — Connect Cursor and show account-scoped Today token consumption** · AFK · Blocked by: S1 · PRD stories: 2, 5, 21, 25, 26, 27, 28, 29, 35, 61, 66
3. **S3 — Show Codex account quotas without modifying shared credentials** · AFK · Blocked by: S1 · PRD stories: 22, 23, 24, 30, 31, 39, 40
4. **S4 — Validate real account access, scope, and historical coverage** · HITL · Blocked by: S2, S3 · PRD stories: 21, 22, 23, 24, 25, 26, 27, 28, 29, 51, 67
5. **S5 — Import and resume Codex history with coverage-aware totals** · AFK · Blocked by: S4 · PRD stories: 18, 32, 33, 34, 35, 36, 50, 51, 52, 53, 54, 55
6. **S6 — Import and resume paginated Cursor history within its workspace** · AFK · Blocked by: S4 · PRD stories: 18, 21, 27, 28, 29, 33, 35, 36, 50, 51, 52, 53, 54
7. **S7 — Compare token consumption across aligned dashboard periods** · AFK · Blocked by: S5, S6 · PRD stories: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 60, 65
8. **S8 — Switch the Today dashboard to comparable Estimated Cost** · AFK · Blocked by: S4 · PRD stories: 4, 41, 42, 43, 45, 46, 47
9. **S9 — Show workspace-scoped Cursor quota remaining and reset times** · AFK · Blocked by: S4 · PRD stories: 28, 39, 40
10. **S10 — Compare Estimated Cost across all three periods** · AFK · Blocked by: S7, S8 · PRD stories: 4, 12, 13, 14, 15, 16, 17, 19, 44, 48
11. **S11 — Refresh independently while preserving honest cached results** · AFK · Blocked by: S5, S6, S9 · PRD stories: 24, 26, 50, 52, 53, 55, 56, 57, 58, 59, 60, 63
12. **S12 — Refresh pricing daily and keep estimates usable offline** · AFK · Blocked by: S8, S10 · PRD stories: 44, 45, 46, 47, 48, 49
13. **S13 — Inspect provider breakdowns and charts in the complete native dashboard** · AFK · Blocked by: S3, S7, S9, S10, S11, S12 · PRD stories: 1, 4, 5, 12, 13, 20, 21, 28, 34, 36, 37, 38, 39, 40, 45, 47, 52, 59, 64, 65, 66
14. **S14 — Accept the real-data MVP on Pedro’s Mac** · HITL · Blocked by: S13 · PRD stories: 23, 29, 31, 33, 35, 51, 53, 54, 61, 62, 63, 64, 66, 67

## Draft issue bodies

S identifiers are review references, not GitHub issue numbers. After approval, publish in dependency order and replace these identifiers with actual blocking issue references. Do not modify or close the parent PRD.

### S1: Show persisted Codex token consumption for Today

Type: AFK. User stories: 1, 2, 3, 20, 32, 34, 35, 36, 55, 61, 62, 63, 66.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Deliver the first real vertical path: read local Codex activity, normalize it into a transactional on-device usage ledger, and show Today token consumption in the native menu bar panel. Establish only the shared contracts this path needs and the automated integration harness. Replace sample data in normal presentation; leave Cursor disconnected. Do not start the legacy system-metrics lifecycle.

## Acceptance criteria

- [ ] Today totals reconcile with sanitized Codex source records, including inclusive cached input and repeated cumulative observations.
- [ ] Show local device activity, unavailable categories, disconnected/empty/access-error states, and the observation cutoff; absence of records alone is not proof of complete coverage.
- [ ] Persist and reopen time-granular usage with stable source identity; importing the same records twice does not inflate the displayed total.
- [ ] Do not retain prompts, responses, source code, or credentials; do not rewrite Codex authentication.
- [ ] The panel shows real imported data, remains responsive, builds natively, and has source-to-persisted-dashboard integration coverage.

## Blocked by

None - can start immediately.

### S2: Connect Cursor and show account-scoped Today token consumption

Type: AFK. User stories: 2, 5, 21, 25, 26, 27, 28, 29, 35, 61, 66.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Add an app-owned Cursor browser connection and credential renewal path that retrieves Today usage events, persists their timestamps and normalized tokens, and displays Cursor alongside Codex with a combined token donut. Scope data to the selected account/workspace; retain source coverage labels rather than implying account-wide Codex coverage. Implement/test the connection UI and protocol using controlled responses; interactive live proof belongs to S4.

## Acceptance criteria

- [ ] Browser authentication returns to the intended app flow; app-owned credentials are stored in Keychain and omitted from the ledger/logs.
- [ ] Explicitly select one workspace if multiple scopes are exposed, show its identity, and keep reconnecting identities and histories separate.
- [ ] Paginate Today events completely and normalize disjoint input/output/cache buckets without double counting.
- [ ] Provider and combined Today values agree with persisted metadata and distinguish account/workspace Cursor activity from Codex device activity.
- [ ] Controlled authentication, renewal, pagination, rejected scope, reconnection, and aggregation checks pass without live credentials; unsupported scoping is surfaced rather than substituted.

## Blocked by

- S1: Show persisted Codex token consumption for Today

### S3: Show Codex account quotas without modifying shared credentials

Type: AFK. User stories: 22, 23, 24, 30, 31, 39, 40.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Read Codex-owned authentication and retrieve account-scoped quota remaining/reset times into the Codex provider card while local token history remains device-scoped. Expose authentication recovery and account-change confirmation in the UI. Do not introduce an app-owned Codex login or silently renew shared credentials.

## Acceptance criteria

- [ ] Show supported quota windows/reset times separately from token consumption; never infer token counts from quotas.
- [ ] Read configured Codex authentication without writing it; expired credentials direct renewal through Codex.
- [ ] A changed login pauses quota publication until explicit user confirmation; old quota values remain labeled with their original identity and freshness.
- [ ] Changing the login never relabels local token records or removes the device coverage label.
- [ ] Lifecycle tests cover missing/expired authentication, identity changes, failed requests, persisted state, and correctly scoped UI publication.

## Blocked by

- S1: Show persisted Codex token consumption for Today

### S4: Validate real account access, scope, and historical coverage

Type: HITL. User stories: 21, 22, 23, 24, 25, 26, 27, 28, 29, 51, 67.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

With Pedro, connect the implemented flows to real Cursor/Codex sources and demonstrate real Today usage and Codex quota readings in the app. Probe available Cursor history/workspace scoping and Codex history formats, recording sanitized evidence needed by subsequent slices. This is a working integration checkpoint, not a separate research-only report.

## Acceptance criteria

- [ ] Pedro completes Cursor browser login/workspace selection and confirms the displayed identities; real totals are reconciled against representative source records.
- [ ] Read Codex quota authentication without changing its credential files, and verify real local records and account quota readings remain distinct.
- [ ] Probe actual Cursor date-range pagination and availability up to 60 days; record observed coverage without promising unsupported retention.
- [ ] Record supported Cursor quota fields, transcript variants, and observed model/tier evidence without retaining secrets or conversation content.
- [ ] If app-owned authentication or required workspace scoping is not possible, report the concrete conflict for a scope decision before dependent work; do not silently use another account/source.

## Blocked by

- S2: Connect Cursor and show account-scoped Today token consumption
- S3: Show Codex account quotas without modifying shared credentials

### S5: Import and resume Codex history with coverage-aware totals

Type: AFK. User stories: 18, 32, 33, 34, 35, 36, 50, 51, 52, 53, 54, 55.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Extend the Codex-to-dashboard path to available active/archive history for the current and preceding 30-day windows. Import incrementally with durable progress and a 90-day retention policy, while showing partial totals and progress immediately. Harden request/session identity and cumulative accounting against real variants established by S4.

## Acceptance criteria

- [ ] Recursively discover supported active/archive sessions within the configured home, import up to 60 days of available metadata, and retain normalized history for 90 days.
- [ ] Appends, reimports, copied/forked sessions, cumulative updates, file replacement, malformed lines, and incomplete final records do not fabricate or duplicate consumption.
- [ ] Closing/reopening during import resumes durable checkpoints; previously established history remains usable.
- [ ] Dashboard totals and import progress update in bounded background work, with missing/unreadable history explicitly incomplete.
- [ ] Fixture-to-ledger-to-display tests cover adversarial duplicate cases, retained categories, resume, restart, and retention.

## Blocked by

- S4: Validate real account access, scope, and historical coverage

### S6: Import and resume paginated Cursor history within its workspace

Type: AFK. User stories: 18, 21, 27, 28, 29, 33, 35, 36, 50, 51, 52, 53, 54.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Extend Cursor collection to available current/baseline history, retaining event timestamps and workspace ownership through persistence and UI publication. Fetch complete bounded pages/date ranges with durable progress; show coverage and known subtotals while importing rather than waiting for the entire backfill.

## Acceptance criteria

- [ ] Request available history up to 60 calendar days, paginate to verified completion, and retain time-granular metadata for 90 days.
- [ ] Persist import progress so cancellation/restart resumes without repeated charges/tokens or mixed account/workspace histories.
- [ ] Show incomplete/unavailable ranges explicitly; missing pages, malformed responses, and unverified retention never become zero activity.
- [ ] The app remains usable while imported counts and coverage advance; credentials and raw conversation content remain outside the ledger.
- [ ] Tests exercise duplicate pages, page-count mismatches, incomplete ranges, interruption/resume, retention, and source-to-dashboard reconciliation.

## Blocked by

- S4: Validate real account access, scope, and historical coverage

### S7: Compare token consumption across aligned dashboard periods

Type: AFK. User stories: 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 60, 65.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Make Today, Last 7 Days, and Last 30 Days drive the combined/provider token totals and matched-progress previous-period comparisons from the persisted ledger. Use one explicit query context for cutoff, time zone, coverage, and selected period. Persist the period preference and show meaningful zero/unknown comparison states.

## Acceptance criteria

- [ ] Use the exact disjoint local calendar boundaries from the parent PRD, including matching baseline final-day time; do not substitute completed periods or fixed-hour windows.
- [ ] Display neutral absolute/percentage changes for combined/provider totals only where comparable coverage permits.
- [ ] Confirmed zero baseline yields an absolute increase with No previous usage and no percentage; confirmed zero-to-zero yields No change.
- [ ] Missing history is a labeled subtotal, not a zero; combined comparisons cannot silently mix incompatible cutoffs/coverage.
- [ ] Controlled-clock integration tests cover midnight, month/year boundaries, DST, stale cutoff preservation, preference persistence, and exact token differences.

## Blocked by

- S5: Import and resume Codex history with coverage-aware totals
- S6: Import and resume paginated Cursor history within its workspace

### S8: Switch the Today dashboard to comparable Estimated Cost

Type: AFK. User stories: 4, 41, 42, 43, 45, 46, 47.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Add the main Tokens / Estimated Cost selector and value persisted Today consumption for both providers with one immutable pricing-table revision. Show the combined monetary donut and provider estimates, while preserving token accounting and independent quota readings. Begin with validated catalog/bundled rates and explicit unknown-price behavior; dynamic catalog lifecycle belongs to S12.

## Acceptance criteria

- [ ] The main summary and provider values switch metrics, and the selected metric survives restart.
- [ ] Apply comparable API-rate valuation to both tools; do not add provider charges or subscription fees to the estimated total.
- [ ] Expose the pricing date and separately label reported Cursor charges if they appear in details.
- [ ] Unknown model/cache/context/tier rates leave tokens intact, identify unpriced activity, and label priced subtotals Incomplete estimate.
- [ ] Fixture-to-native-presentation tests verify independent expected costs, correct cached-input treatment, complete/partial prices, and unaltered quota values.

## Blocked by

- S4: Validate real account access, scope, and historical coverage

### S9: Show workspace-scoped Cursor quota remaining and reset times

Type: AFK. User stories: 28, 39, 40.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Use verified Cursor account/workspace quota fields to populate its native provider card. Keep the quota measurement independent of token periods and cost valuation, with explicit unavailable states for unsupported fields rather than guessed limits.

## Acceptance criteria

- [ ] Quota/reset rows are derived from supported scoped provider responses and show the selected account/workspace.
- [ ] Switching periods or Tokens / Estimated Cost does not change the underlying quota reading.
- [ ] Unsupported, missing, or malformed quota fields are unavailable, not zero or unlimited by default.
- [ ] Tests connect scoped responses through retained quota state to the displayed card and distinguish failure from a successful zero reading.

## Blocked by

- S4: Validate real account access, scope, and historical coverage

### S10: Compare Estimated Cost across all three periods

Type: AFK. User stories: 4, 12, 13, 14, 15, 16, 17, 19, 44, 48.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Extend the Cost metric to the same aligned selected/baseline windows as Tokens. Query both providers and both periods with one pricing-table revision, publishing coherent totals, differences, and completeness in the dashboard.

## Acceptance criteria

- [ ] Today, Last 7 Days, and Last 30 Days use the same calendar-progress semantics in both metrics.
- [ ] Current/baseline estimates share one rate revision, and provider/combined deltas reconcile with the same query.
- [ ] Missing history and missing pricing are distinct; affected percentages are withheld, never fabricated from zero.
- [ ] Confirmed zero monetary baselines follow the agreed absolute-difference/No previous usage rules.
- [ ] Integration tests independently validate model mix, historical repricing without token changes, conditional-rate gaps, and metric switching.

## Blocked by

- S7: Compare token consumption across aligned dashboard periods
- S8: Switch the Today dashboard to comparable Estimated Cost

### S11: Refresh independently while preserving honest cached results

Type: AFK. User stories: 24, 26, 50, 52, 53, 55, 56, 57, 58, 59, 60, 63.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Deliver automatic five-minute and manual refresh through both collectors, the persisted ledger/snapshots, and the native status/error UI. Keep sources independent, prevent overlapping work, and preserve original data cutoffs on failures while allowing healthy sources to advance.

## Acceptance criteria

- [ ] Refresh while the panel is closed; opening/relaunching shows known cached values immediately with their original age.
- [ ] Manual Refresh honors provider-requested retry delays; bounded work, cancellation, and persisted progress prevent request storms or restart loops.
- [ ] A provider failure preserves its last successful values, identity, cutoff, and error without stopping the other provider.
- [ ] Combined comparisons remain honest when provider freshness diverges; access/authentication/import errors do not erase history or create false zero coverage.
- [ ] Controlled-clock/HTTP/credential-to-UI checks cover backoff, renewal, expired Codex credentials, offline launch, independent failures, and cancellation.

## Blocked by

- S5: Import and resume Codex history with coverage-aware totals
- S6: Import and resume paginated Cursor history within its workspace
- S9: Show workspace-scoped Cursor quota remaining and reset times

### S12: Refresh pricing daily and keep estimates usable offline

Type: AFK. User stories: 44, 45, 46, 47, 48, 49.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Connect the public pricing catalog and verified supplemental rates to cached offline valuation, ledger revaluation, and pricing status in the dashboard. Refresh asynchronously each day without blocking usage collection, pinning one valid revision per displayed query.

## Acceptance criteria

- [ ] Fetch/validate the primary catalog and source-dated verified supplements, retaining the last valid table and a validated bundled fallback.
- [ ] Daily refresh/failure/offline states expose the pricing date; invalid or partial responses do not replace valid known rates.
- [ ] Publishing a new revision revalues selected and baseline periods together without changing retained token consumption.
- [ ] Unknown native Cursor aliases, cache discounts, and conditional tiers stay unpriced unless verified; no old historical supplement is treated as current by assumption.
- [ ] Tests cover failed refresh, restart/offline reuse, immutable query revisions, independently calculated repricing, and persistent incomplete-estimate presentation.

## Blocked by

- S8: Switch the Today dashboard to comparable Estimated Cost
- S10: Compare Estimated Cost across all three periods

### S13: Inspect provider breakdowns and charts in the complete native dashboard

Type: AFK. User stories: 1, 4, 5, 12, 13, 20, 21, 28, 34, 36, 37, 38, 39, 40, 45, 47, 52, 59, 64, 65, 66.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

Complete the screenshot-inspired compact dashboard with expandable token categories, model breakdowns, and selected-period charts derived from the same real ledger queries as its donut, totals, and comparisons. Carry identities, source coverage, pricing, import, and freshness information through every view; retain independent quota bars.

## Acceptance criteria

- [ ] Summary/legend/provider/model/category/chart values reconcile under metric/period switching and the same query cutoff/rate revision.
- [ ] Expanders show hourly buckets for Today and daily buckets for Last 7 Days/Last 30 Days, preserving unavailable categories and incomplete states.
- [ ] The layout follows the supplied reference while excluding forecasts/notifications and normal-flow fictional data.
- [ ] Keyboard navigation, accessible chart descriptions, long localized numbers, empty/partial/error states, and scrolling work on constrained screens.
- [ ] Native UI smoke checks and ledger-to-presentation assertions verify the complete path; no separate mock-only UI is accepted.

## Blocked by

- S3: Show Codex account quotas without modifying shared credentials
- S7: Compare token consumption across aligned dashboard periods
- S9: Show workspace-scoped Cursor quota remaining and reset times
- S10: Compare Estimated Cost across all three periods
- S11: Refresh independently while preserving honest cached results
- S12: Refresh pricing daily and keep estimates usable offline

### S14: Accept the real-data MVP on Pedro’s Mac

Type: HITL. User stories: 23, 29, 31, 33, 35, 51, 53, 54, 61, 62, 63, 64, 66, 67.

## Parent

https://github.com/predo-soares/stats/issues/1

## What to build

With Pedro, validate the complete personally installed native app against both real sources and the approved reference layout. Exercise actual sign-in/access, representative accounting/comparisons, restarts, recovery, and responsiveness. Resolve discrepancies or record genuine source limits without fabricating completeness.

## Acceptance criteria

- [ ] Reconcile representative real day/model/category totals and matched baselines, including cached counters and duplicate cases, against independently selected source records.
- [ ] Verify history/checkpoints survive restart, subsequent refresh is incremental, Cursor identities remain isolated, and Codex authentication is unchanged.
- [ ] Where 60-day coverage is unavailable, demonstrate explicit unavailable comparisons; missing source support must not be claimed as a completed supported capability.
- [ ] Inspect native layout, metric switching, charts, scrolling, accessibility, and responsiveness during import and with the panel open/closed.
- [ ] Confirm local-only retained metadata, no credential/conversation leakage or accidental export bundling, native build/signing viability, and no modification of unrelated user changes.
- [ ] Document acceptance evidence and remaining source limitations; a fixture preview or passing build alone is not acceptance.

## Blocked by

- S13: Inspect provider breakdowns and charts in the complete native dashboard
