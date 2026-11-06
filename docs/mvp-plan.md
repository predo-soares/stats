# Cursor and Codex MVP

Status: scope agreed through Q30 and synthesized into [PRD issue #1](https://github.com/predo-soares/stats/issues/1). Test boundaries confirmed. This discovery document is supporting context; the published PRD captures the final specification. Application implementation has not been requested.

## Confirmed decisions

- Build a native Swift macOS menu bar application for Cursor and Codex.
- Token consumption is the primary concern; quota remaining and reset times are secondary.
- Keep token consumption, quota remaining, reported charges, and estimated costs distinct.
- Label estimated costs explicitly.
- The first user is Pedro, using the application on his own Mac.
- Keep collected usage history on the device. No backend, cloud sync, or product analytics in the MVP.
- Network requests for provider authentication, usage retrieval, and model pricing are allowed.
- Use the supplied OpenUsage screenshot as a visual reference. It is not a complete functional specification.
- Learn from OpenUsage and CodexBar, selecting suitable collection, reliability, and presentation practices rather than adopting either implementation wholesale.
- Codex token accounting covers locally available session transcripts on this Mac. Cursor token accounting covers activity reported for the signed-in account and may include other devices. Explicitly label coverage rather than implying equivalent scopes.
- Reuse Codex's existing login without modifying its shared credentials. Delegate renewal of expired credentials to Codex.
- Give Cursor a separate browser sign-in with app-owned credentials. The app manages renewal of its own Cursor login.
- Retain usage metadata only: timestamps, model identifiers, token counts, costs, and identifiers required for deduplication. Do not retain copies of prompts, responses, or source code. Reading local transcript records does not authorize retaining their content.
- Support one active account per tool, with no account switcher. Label Codex token history as local device activity; do not assign all local transcripts to the active login. Account quota readings remain account-scoped.
- Dashboard periods are Today, Last 7 Days, and Last 30 Days. This supersedes the initially proposed Today/Yesterday/Last 30 Days selector. Last 7 Days means today plus the previous six local calendar days, not the previous Monday–Sunday week. Last 30 Days means today plus the previous 29 local calendar days.
- Each dashboard period must compare token consumption with the preceding equivalent period, aligned to the same elapsed portion. Today compares through the current local time with Yesterday through that local time. The longer windows likewise end their comparison at the matching local time on the baseline window's final day, rather than comparing an unfinished window with a completed one.
- Show comparisons for the combined total and each provider: absolute token difference and percentage change, using neutral higher/lower language. Place the combined comparison beside the summary and provider comparisons in their respective sections.
- Use the Mac's local time zone. Daily totals and model breakdowns are in scope; project/session drill-down is deferred.
- Include cached tokens in total consumption, preserve available breakdowns, and avoid adding overlapping counters twice. Missing categories are unavailable, not fabricated zeroes.
- Retain 90 days of normalized usage history. Older-history browsing is deferred.
- Initial import must cover at least the current and previous 30-day periods (60 calendar days), where source data is available. This follows from the comparison requirement and supersedes the earlier 30-day import proposal. Source coverage and initial-import completion must remain explicit.
- When either comparison period has missing data, show the known subtotal with an Incomplete history label and withhold the percentage comparison. A combined comparison requires comparable coverage for both providers; missing records must not silently become zero usage.
- For a confirmed zero baseline and positive current usage, show the absolute token increase and No previous usage, with no percentage. If both periods are confirmed zero, show No change.
- The main dashboard has a Tokens / Cost metric selector. Selecting Cost changes the main view rather than restricting costs to provider details. This explicitly supersedes the earlier details-only cost presentation decision.
- Cost means estimated API-rate value of consumption for both Cursor and Codex, excluding subscription fees. Label the selected view Estimated Cost, keep this value separate from billing, and do not combine reported Cursor charges with Codex estimates. Cursor reported charges may appear separately labeled in provider details.
- Estimated Cost has the same aligned previous-period comparisons as Tokens. Apply the same pricing table to both periods; pricing updates may revalue historical estimates. Make the pricing date available so the comparison reflects consumption and model mix rather than different pricing dates.
- Count tokens for unpriced models, but exclude their unknown value from the priced subtotal. Mark the Cost result Incomplete estimate, identify unpriced models, and withhold percentage comparisons affected by missing prices. Unknown prices never become zero-dollar usage.
- Keep the main dashboard compact, following the screenshot's structure. Each provider expands to show token categories, model breakdowns, and a period chart. Chart buckets are hourly for Today and daily for Last 7 Days and Last 30 Days. Quota bars are independent of the Tokens / Cost selection.
- Make the dashboard usable immediately while importing available history in the background. Show known totals, import progress, and unavailable comparisons until sufficient coverage is established. Import up to 60 days using bounded background work and resume interrupted imports.
- If Cursor exposes multiple personal/team workspaces, require explicit selection of one workspace during connection. Display the selected workspace beside the account and keep its history separate. No workspace switcher in the MVP; changing the selection requires reconnecting.
- The MVP is a local Mac app outside the Mac App Store, with App Sandbox disabled. Collection remains limited to the agreed data sources. Do not require broad Full Disk Access by default; surface specific access failures.
- If Codex's login changes, pause account-scoped quota readings until the user confirms the new account; local token history remains device-scoped. Changing Cursor accounts requires reconnecting, with histories kept separate.
- Refresh every five minutes while the app is running, including while the panel is closed. Provide manual Refresh, show cached data immediately with its age, and honor provider retry delays even on manual refresh.
- Show remaining quota and provider-reported reset times. Defer predicted exhaustion times, pace warnings, and notifications from the MVP, despite their presence in the visual reference.
- Refresh a public pricing catalog daily; supplement it only with verified rates, retain the last valid table offline, and show its date. Unknown rates remain unpriced; custom price editing is deferred.
- Preserve last successful values on refresh failure, clearly showing their age and the affected provider's error. Retained comparisons keep their original data cutoff. One provider's failure does not prevent the other from updating.
- Completion requires real Cursor and Codex data, persistence across restart, correct comparisons where source coverage permits, and reconciliation against source records including duplicate-token cases. A sample-data dashboard does not meet MVP acceptance.
- During implementation, reuse useful presentation components from the exploratory UI while replacing sample-data assumptions and unapproved behavior. Preserve unrelated user changes.
- Application implementation remains paused until the user confirms the consolidated plan.

## Existing implementation caveat

An earlier UI implementation was made before implementation was requested. Its sample data, behavior, defaults, and architecture are unapproved exploratory work and do not establish MVP requirements. Leave those application changes untouched during planning. After approval, reusable presentation pieces may be adapted to this plan; their fixtures and defaults are not requirements.

## Evidence available

Source inspection was performed using GitHub CLI, without live provider authentication tests:

- [OpenUsage at 1acc905](https://github.com/robinebers/openusage/tree/1acc9059b5ac3a6468d501647a151466cdfa024a): provider HTTP clients and response mappers, app-owned credentials, account snapshots, backoff, and stale-data handling. Its current architecture uses provider-reported usage rather than native local token scanners.
- [CodexBar at 897bff3](https://github.com/steipete/CodexBar/tree/897bff31731bb4b21b105f6e8bf4c32a8a8bf095): separate quota retrieval and native local token accounting, incremental scans, deduplication, and cost estimates.
- [OpenUsage 0.7.16](https://github.com/robinebers/openusage/tree/v0.7.16): screenshot-era presentation reference, including provider donut, period selection, quota bars, and usage trends. This differs from current OpenUsage.

### Comparison feasibility findings

- Cursor usage events include millisecond timestamps and paginated date-range queries. OpenUsage's existing history path reduces those events to daily totals and fetches 30 days. Our aligned comparisons need time-granular retained metadata or cutoff queries, plus a wider import. A guaranteed 60-day retention/coverage contract is not established by the inspected source; validate availability rather than promise it. [Client](https://github.com/robinebers/openusage/blob/1acc9059b5ac3a6468d501647a151466cdfa024a/Sources/OpenUsage/Providers/Cursor/CursorUsageClient.swift#L84-L103), [history source](https://github.com/robinebers/openusage/blob/1acc9059b5ac3a6468d501647a151466cdfa024a/Sources/OpenUsage/Providers/Cursor/CursorHistorySource.swift#L70-L96).
- CodexBar retains token-event timestamps and provides hourly and exact-timestamp buckets. Comparison feasibility still depends on locally available transcripts/cache, not an account-wide history guarantee. [Temporal buckets](https://github.com/steipete/CodexBar/blob/897bff31731bb4b21b105f6e8bf4c32a8a8bf095/Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner%2BTemporalBuckets.swift#L53-L93).
- Previous comparison windows must be disjoint from current windows. Do not reuse OpenUsage's overlapping prior-days summary as a previous-period baseline.

### Pricing feasibility findings

- CodexBar separates a cached models.dev catalog, bundled fallback rates, and asynchronous refresh. Its current catalog TTL is 24 hours, with cached rates preserved on refresh failure. The agreed daily-refresh/offline policy follows this pattern; verify model resolution and fallback provenance during implementation. [Pricing documentation](https://github.com/steipete/CodexBar/blob/897bff31731bb4b21b105f6e8bf4c32a8a8bf095/docs/model-pricing.md#L12-L35).
- CodexBar normally prefers Cursor's reported tokenUsage.totalCents, whereas our agreed Cost metric uses a shared-rate valuation. Its fallback estimator does not supply Auto/Composer mappings. Historical OpenUsage PR827 includes supplementary native-model prices, but those historical rates are not verified current prices. Do not copy reported charges or old supplement prices into our estimate as if equivalent/current. [Cursor fallback](https://github.com/steipete/CodexBar/blob/897bff31731bb4b21b105f6e8bf4c32a8a8bf095/Sources/CodexBarCore/Providers/Cursor/CursorUsageEventsFetcher.swift#L742-L786), [historical PR](https://github.com/robinebers/openusage/pull/827).
- Normalize source counters before applying rates: the inspected Cursor event categories are disjoint; Codex input includes cached input. Do not inherit fallback assumptions that silently price missing cache rates as ordinary input. Verify available context/tier evidence before applying conditional rates.

## Architecture decisions

- [Compare consumption at shared API rates](adr/0001-compare-consumption-at-shared-api-rates.md)

## Proposed technical design

These implementation choices satisfy the agreed product scope and are included in the final plan review; they are not claims that the current prototype implements the collectors.

- **Application shell:** SwiftUI dashboard hosted by AppKit's menu bar panel, with Swift Charts for visualizations. Reuse suitable existing presentation code without starting the old system-metric sampling lifecycle.
- **Collectors:** independent Cursor and Codex workers, isolated from UI publication. Use Foundation URLSession and Codable for HTTP; stream local JSONL rather than reading whole transcript trees into memory. No ccusage, Node.js, or continuously running CLI subprocess is required for normal refresh.
- **Credentials:** app-owned Cursor credentials in Keychain; existing Codex authentication read without modification. Never persist access tokens in the usage ledger, export them, or log them. Validate browser return, token renewal, account identity, and workspace scoping against the reference flow before relying on them.
- **Usage ledger:** local SQLite, accessed through native SQLite3, with transactional writes. Retain normalized time-granular metadata and provenance for 90 days, durable import progress, source file identities/offsets, and coverage intervals. Do not reduce the only retained representation to daily totals: same-time comparisons need finer timestamps.
- **Accounting:** source-specific parsers feed explicit, non-overlapping token categories. Codex cached input must be separated from inclusive input before addition/pricing; Cursor's disjoint buckets must not be subtracted twice. Preserve unknown fields as unavailable. Handle repeated/cumulative records, retries, reimports, file replacement, truncated tails, and copied/forked sessions without inventing consumption. Store identifiers required for accounting without retaining conversation content.
- **Pricing:** use models.dev as the primary public catalog, with source-dated, verified supplementary rates and validated bundled fallback data. Retain the last valid catalog on failure. Unknown model, cache, context, or tier prices must not receive arbitrary substitutions. Pin one catalog revision per query so both periods and both providers use consistent rates. Compute estimates from ledger tokens, not provider billing fields.
- **Queries:** a shared period/comparison layer drives summary, provider totals, model/category breakdowns, charts, and copyable values. Preserve the selected data cutoff, local time-zone rules, coverage state, and pricing revision with each projection. Combined totals sum the explicitly labeled tool coverages; they do not claim complete account-wide or universal cross-provider request attribution.
- **Refresh:** five-minute cadence with one in-flight import/refresh per source, cancellation, bounded concurrency, persisted progress, and provider-specific backoff. Manual refresh may bypass local freshness caching but never a provider-requested retry delay. Import and pricing refresh must not block the main actor.
- **Failures:** distinguish disconnected, importing, fresh, stale, access denied, authentication required, incomplete history, and incomplete estimate. Keep healthy provider updates independent. Never erase known history because a request failed, or treat unreadable/malformed records as confirmed zero consumption.

### Exact period boundaries

Let D be the current local calendar date and T the data cutoff's local time. Use calendar arithmetic rather than fixed 24-hour multiples so local day boundaries remain correct across daylight-saving changes.

| Selection | Current window | Baseline window |
| --- | --- | --- |
| Today | Start of D through T on D | Start of D−1 through T on D−1 |
| Last 7 Days | Start of D−6 through T on D | Start of D−13 through T on D−7 |
| Last 30 Days | Start of D−29 through T on D | Start of D−59 through T on D−30 |

The windows have equivalent calendar progress and do not overlap. Their unused remainder is intentionally excluded from comparison. If cached data is displayed, T remains that snapshot's cutoff; elapsed wall time alone does not make the data current. Percent change is (current − baseline) / baseline only when baseline is positive and both compared totals have sufficient coverage. Apply the agreed zero/unknown rules otherwise.

## Implementation phases after approval

### 1. Prove collection and access

- Verify Cursor's app-owned browser login and renewal, available account/workspace identifiers, timestamped event pagination, quota fields, and available 60-day history.
- Verify read-only Codex login access, recursive active/archive discovery under CODEX_HOME, event formats, account identity, and quota retrieval.
- Establish token semantics and pricing evidence for models actually observed, especially Cursor Auto/Composer and any context/tier modifiers.
- Produce narrowly scoped sanitized fixtures containing usage metadata, never prompt content or credentials.

**Exit:** both real sources can be read within the approved access boundary. Record observed coverage and unsupported fields explicitly. If account/workspace scoping or another required capability cannot be established, report it for a scope decision rather than silently substitute a different source or identity.

### 2. Build durable accounting

- Implement the ledger, source ownership, coverage tracking, import checkpoints, and retention.
- Add source-specific normalization and incremental/idempotent imports.
- Import available current/baseline history without blocking dashboard use; resume after restart.

**Exit:** importing the same records twice does not change totals, appended activity is counted once, cached counts are not duplicated, and restart resumes without losing established history. Missing/invalid data remains distinguishable from confirmed inactivity.

### 3. Implement comparisons and estimates

- Add shared time-window queries, model/category aggregates, hourly/daily chart buckets, and aligned previous-period comparisons.
- Add catalog refresh/cache, verified rates, and API-rate valuation independent of billing.
- Propagate history/pricing coverage into provider and combined results.

**Exit:** exact fixture totals, zero-baseline behavior, incomplete states, time-zone boundaries, and repricing are verified. Both periods use the same catalog revision; token totals survive absent prices.

### 4. Connect the native dashboard

- Adapt the screenshot's summary donut, period selector, provider cards, quota bars, trends, and expanders to real query results.
- Add Tokens / Estimated Cost selection, absolute/percentage differences, token/model breakdowns, pricing information, source labels, account/workspace identity, and import/freshness states.
- Provide connection/reconnection, manual refresh, and scoped access/authentication errors. Persist presentation preferences.
- Keep sample fixtures in previews/verification only; the normal app must not present fictional account usage as real.
- Ensure screen-bounded scrolling, keyboard access, accessible chart descriptions, and legible zero/empty/partial states.

**Exit:** every displayed number and comparison is traceable to the ledger or a labeled quota response. Switching metrics never changes quota readings or invents missing prices.

### 5. Validate the working MVP

- Reconcile representative real Cursor events and local Codex records with displayed day/model totals, including cache categories and duplicates.
- Verify restart, interrupted import, offline launch, expired login, account change, failed/rate-limited refresh, missing prices, and insufficient baseline history.
- Check performance with the panel open and closed during a bounded initial import and a normal refresh; inspect responsiveness and redundant scans/requests.
- Build and manually inspect the native app at supported screen sizes. Preserve unrelated working-tree changes and avoid bundling local exports or fixtures unintentionally.

**Exit:** acceptance criteria below pass, with genuine source limits documented rather than hidden by fabricated values.

## Acceptance criteria

- [ ] Both real sources connect and populate usage; Cursor account/workspace identity and Codex device-history scope are visible.
- [ ] Codex credentials are not rewritten, Cursor credentials remain app-owned, and account changes cannot silently relabel history or quotas.
- [ ] Ledger/history/checkpoints survive restart; imports are incremental, bounded, resumable, and idempotent.
- [ ] Today, Last 7 Days, and Last 30 Days use the specified local calendar windows and matched-progress baselines.
- [ ] Combined/provider totals, token categories, model breakdowns, charts, and comparisons agree with the same ledger projection.
- [ ] Cached/overlapping token counters and duplicated source records are not counted twice.
- [ ] Confirmed zero usage, missing history, unavailable categories, stale data, and unpriced activity have distinct presentation.
- [ ] Estimated Cost uses consistent API rates across tools/periods, exposes pricing date, and excludes subscription fees and reported billing from the combined valuation.
- [ ] Quota/reset readings remain separate from consumption and pricing, without exhaustion forecasts or notifications.
- [ ] Five-minute/manual refresh, retry delays, offline values, errors, and independent provider updates behave as agreed.
- [ ] Only approved usage metadata is retained; no copied prompts, responses, source code, or credentials enter the ledger or logs.
- [ ] The normal dashboard uses real data; sample-data rendering alone cannot satisfy acceptance.
- [ ] Native build, accounting/comparison regression checks, and manual visual/accessibility/responsiveness checks pass.

Source-retention limits do not authorize fabricated completeness. If 60 days are unavailable, a correctly labeled unavailable comparison is expected behavior; real-data accounting and available comparisons must still reconcile.

## Deferred from the MVP

- Other tools/providers, multiple active accounts, and account/workspace switchers.
- Backend, cloud sync, product analytics, App Store distribution, and automatic broad Full Disk Access requests.
- Conversation archives, project/session drill-down, and browsing history older than the agreed dashboard periods.
- Exhaustion forecasts, pace warnings, and notifications.
- Subscription-invoice reconciliation, combined billed-spend totals, and custom price editing.

## Remaining technical validations

These are implementation facts to establish in phase 1, not unresolved product decisions:

- Actual Cursor 60-day retention, complete pagination, exact account/workspace scoping, browser login/renewal behavior, and supported quota fields.
- Current Codex transcript variants, fork/replay identity, safe quota access, and local history availability.
- Verified prices/aliases for Cursor-native models, required cache/context/tier evidence, and trustworthy catalog fallbacks.
- Personal build signing, existing project resource inclusion, and the minimum macOS version needed by the retained implementation.

Any finding that contradicts agreed scope must be brought back as a concrete decision. Do not silently replace a requirement. After final confirmation, execute phases in order; do not treat this document's existence or the exploratory UI as authorization to start early.
