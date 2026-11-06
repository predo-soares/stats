## Problem Statement

Pedro uses Cursor and Codex on his Mac but lacks one dependable view of how many tokens he consumes, which models contribute to that activity, and how consumption is changing. Subscription quota percentages do not provide token counts. Reported charges, subscription fees, and the estimated API-rate value of consumption answer different questions and must not be presented as interchangeable money values.

The existing application originated as a system-metrics menu bar utility. An exploratory LLM dashboard was built before implementation was requested; it uses sample data and is not evidence that real collection, accounting, authentication, or comparisons work. The MVP must deliver trustworthy live usage rather than merely reproduce that preview.

The available sources have different coverage: Codex transcripts describe local device activity and can span multiple logins; Cursor reports activity for a connected account/workspace and may include other devices. Missing history, incomplete pagination, stale snapshots, duplicate records, and unknown prices can all make a plausible-looking total misleading.

## Solution

Build a native Swift macOS menu bar application for Pedro's personal use, supporting Cursor and Codex only. Keep the main dashboard close to the supplied OpenUsage reference: a provider donut summary, period selector, provider cards, quota bars, compact trends, and expandable details.

The dashboard switches between Tokens and Estimated Cost. It offers Today, Last 7 Days, and Last 30 Days; every selection compares the combined total and each provider against the preceding equivalent period at the same calendar progress. Estimated Cost values both providers' token consumption at one consistent API-rate table, excludes subscription fees, and remains distinct from reported billing.

Collect Cursor data through an app-owned browser login and provider APIs. Read Codex's existing login without modifying it, scan available local session transcripts incrementally, and retrieve account quotas separately. Keep the usage ledger on-device, import available current/baseline history in the background, retain 90 days, and refresh every five minutes while the app runs. Show coverage, freshness, import progress, and errors explicitly; incomplete data never becomes fabricated zero usage.

## User Stories

1. As Pedro, I want to open my usage dashboard from the macOS menu bar, so that I can inspect consumption without leaving my work.
2. As Pedro, I want the MVP to track Cursor and Codex, so that it focuses on the two tools I use.
3. As Pedro, I want Tokens to be the primary measurement, so that subscription quotas do not obscure actual consumption.
4. As Pedro, I want to switch the dashboard between Tokens and Estimated Cost, so that I can inspect volume and its API-rate value in the same layout.
5. As Pedro, I want a provider donut and matching totals, so that I can understand the contribution of each tool.
6. As Pedro, I want Today, Last 7 Days, and Last 30 Days selections, so that I can examine short-term and sustained consumption.
7. As Pedro, I want the periods to follow my Mac's local calendar, so that the boundaries match my working day.
8. As Pedro, I want Last 7 Days to include today and the previous six days, so that the label is distinct from a previous calendar week.
9. As Pedro, I want Last 30 Days to include today and the previous 29 days, so that its meaning is predictable.
10. As Pedro, I want Today compared with yesterday through the same local time, so that an unfinished day is not compared with a completed one.
11. As Pedro, I want the longer periods compared at the same calendar progress, so that their baselines are equally meaningful.
12. As Pedro, I want absolute and percentage differences for the combined total, so that I can quantify the overall change.
13. As Pedro, I want those differences for each provider, so that I can see which tool explains the change.
14. As Pedro, I want higher/lower language rather than good/bad judgments, so that productive increased usage is not treated as a failure.
15. As Pedro, I want a zero baseline explained without an infinite percentage, so that comparisons remain understandable.
16. As Pedro, I want confirmed zero-to-zero activity shown as No change, so that genuine inactivity is clear.
17. As Pedro, I want missing baseline history distinguished from zero usage, so that unavailable activity cannot produce a false increase.
18. As Pedro, I want known subtotals marked Incomplete history when coverage is missing, so that I can use available information without mistaking it for a full total.
19. As Pedro, I want combined comparisons withheld when both providers lack comparable coverage, so that a partial source cannot distort the apparent change.
20. As Pedro, I want Codex history labeled as local device activity, so that I do not mistake it for complete account-wide consumption.
21. As Pedro, I want Cursor's account/workspace coverage labeled, so that I know it may include activity from other devices.
22. As Pedro, I want to reuse my existing Codex login, so that I do not need a second login for account quota reads.
23. As Pedro, I want the app to leave shared Codex credentials unchanged, so that it does not interfere with Codex's ownership of authentication.
24. As Pedro, I want expired Codex authentication to direct me to renew through Codex, so that recovery follows the owning tool.
25. As Pedro, I want Cursor browser authentication owned by this app, so that Cursor usage retrieval does not depend on modifying another tool's credentials.
26. As Pedro, I want app-owned Cursor credentials kept in Keychain and renewed by the app, so that normal use does not require repeated login.
27. As Pedro, I want to select one Cursor workspace when multiple scopes exist, so that personal and team activity are not silently mixed.
28. As Pedro, I want the selected account/workspace visible, so that I can recognize the source of displayed activity.
29. As Pedro, I want changing Cursor accounts or workspaces to require reconnecting and keep histories separate, so that existing activity is not reassigned to a new identity.
30. As Pedro, I want a changed Codex login to pause account quota reads until I confirm it, so that the displayed account does not change silently.
31. As Pedro, I want Codex device history to retain its device scope after a login change, so that it is not falsely attributed to the new account.
32. As Pedro, I want locally available Codex active and archived sessions included, so that completed work is not lost from accounting.
33. As Pedro, I want repeated imports, copied sessions, and cumulative records counted correctly, so that duplicate data cannot inflate totals.
34. As Pedro, I want cached tokens included in consumption and visible separately, so that I understand their contribution.
35. As Pedro, I want overlapping source counters counted only once, so that inclusive input counters and cached input do not inflate consumption.
36. As Pedro, I want unavailable token categories labeled rather than replaced by zeroes, so that source limitations remain visible.
37. As Pedro, I want to expand each provider for token categories and model breakdowns, so that I can understand the composition of its total.
38. As Pedro, I want an hourly chart for Today and daily charts for longer periods, so that I can identify when activity occurred.
39. As Pedro, I want quota remaining and provider-reported reset times separate from token/cost measurements, so that I can also understand subscription availability.
40. As Pedro, I want quota readings unchanged when switching Tokens and Estimated Cost, so that these independent measurements stay consistent.
41. As Pedro, I want Estimated Cost to use comparable model API rates for both tools, so that the combined valuation has one meaning.
42. As Pedro, I want subscription fees excluded from Estimated Cost, so that I do not mistake it for my bill.
43. As Pedro, I want reported Cursor charges separately labeled if displayed in details, so that billed amounts are not confused with API-rate valuation.
44. As Pedro, I want both sides of a cost comparison valued with the same pricing table, so that changes reflect consumption and model mix rather than different pricing dates.
45. As Pedro, I want the pricing date available, so that I can assess the age of an estimate.
46. As Pedro, I want token counts preserved for unpriced models, so that incomplete pricing does not hide consumption.
47. As Pedro, I want an Incomplete estimate label and a list of unpriced models, so that a priced subtotal is not presented as a complete monetary value.
48. As Pedro, I want affected cost percentages withheld when prices are missing, so that unknown prices cannot become false savings.
49. As Pedro, I want prices refreshed daily with the last valid table available offline, so that a pricing outage does not erase useful estimates.
50. As Pedro, I want the dashboard usable while historical activity imports, so that first launch does not block on a long scan or API backfill.
51. As Pedro, I want available history imported for both current and previous 30-day periods, so that longer comparisons can become available.
52. As Pedro, I want import progress and coverage shown, so that I understand why some comparisons are not ready.
53. As Pedro, I want interrupted imports to resume, so that restarting the app does not restart all collection work.
54. As Pedro, I want 90 days of normalized history retained locally, so that recent activity survives source changes and relaunches within the retention policy.
55. As Pedro, I want cached data displayed immediately after launch, so that I do not wait for a successful network request to inspect known activity.
56. As Pedro, I want automatic five-minute refreshes even while the panel is closed, so that the next opening shows recent data.
57. As Pedro, I want a manual Refresh action that honors provider retry delays, so that I can request an update without amplifying rate limiting.
58. As Pedro, I want independent provider refreshes, so that a Cursor failure does not prevent Codex updates or vice versa.
59. As Pedro, I want last successful values preserved with age and provider-specific errors, so that outages do not erase my history or look like fresh data.
60. As Pedro, I want cached comparisons to retain their data cutoff, so that the clock alone cannot make old observations appear current.
61. As Pedro, I want my ledger to exclude prompts, responses, source code, and credentials, so that tracking usage does not create a conversation archive.
62. As Pedro, I want all retained history on my Mac without a backend, sync, or product analytics, so that the MVP respects the agreed local data boundary.
63. As Pedro, I want specific file-access errors without broad Full Disk Access being required by default, so that I understand the access actually needed.
64. As Pedro, I want a scrollable, keyboard-accessible dashboard with accessible chart summaries, so that it remains usable on my screen and with assistive tools.
65. As Pedro, I want my selected period and metric retained, so that the dashboard returns to my working context.
66. As Pedro, I want the normal dashboard to show real usage rather than fictional fixtures, so that a polished preview is not mistaken for a functioning tracker.
67. As Pedro, I want representative displayed totals reconciled against real source records, so that I can trust the accounting before relying on the app.

## Implementation Decisions

- **Platform and shell:** retain a native Swift macOS app using SwiftUI, an AppKit-owned menu bar panel, and Swift Charts. The personal MVP runs outside the Mac App Store with App Sandbox disabled. Do not start legacy system-metric sampling as part of the usage dashboard. Reuse useful exploratory presentation components, while replacing fixtures and unapproved assumptions; preserve unrelated working-tree changes.
- **Collection boundaries:** build independent Cursor and Codex collectors, a durable usage ledger, pricing catalog, shared comparison/query service, refresh coordinator, and dashboard presentation model. Keep collection, persistence, and price refresh off the main UI actor. Normal operation does not require ccusage, Node.js, or a continuously running CLI process.
- **Cursor contract:** use an app-owned browser login and renewal flow with credentials in Keychain. Fetch timestamped usage events with complete pagination and maintain the selected account/workspace identity. Select one workspace explicitly when multiple scopes are exposed. Do not substitute another account, workspace, or source if the intended scope cannot be established.
- **Codex contract:** read existing Codex authentication without rewriting credentials; delegate renewal to Codex. Discover active and archived local transcripts recursively within the configured Codex home, scan incrementally, and retrieve account quotas separately. Local token records are device-scoped, not automatically attributed to the currently authenticated account.
- **Identity changes:** require reconnection for Cursor account/workspace changes and keep their histories separate. Detect a changed Codex login, suspend account-scoped quota publication until confirmation, and retain the device scope of token history. No multi-account or workspace switcher is included.
- **Ledger contract:** use native SQLite for transactional, on-device storage of normalized usage metadata, source/provenance identities, timestamps, model identifiers, token categories, pricing inputs, coverage intervals, and resumable import checkpoints. Retain 90 days. Preserve time-granular accounting; daily totals alone are insufficient for same-time comparisons. Do not retain copied conversation content or credentials.
- **Accounting contract:** normalize source counters into non-overlapping categories before summing or pricing. The inspected Cursor token buckets are disjoint; inspected Codex input includes cached input. Preserve unavailable categories as unknown. Handle cumulative/streamed records, duplicate requests, repeated imports, copied/forked sessions, file replacement, incomplete final records, and retries without fabricated or duplicated consumption. Keep source identity and coverage distinct from account quota identity.
- **Import behavior:** import up to 60 calendar days of available activity for current/baseline queries, using bounded, resumable background work. Present cached/known data immediately with import progress. Enumerating no records is not, by itself, proof that all required historical coverage is complete. Malformed, unreadable, and unreturned records are not confirmed inactivity.
- **Periods:** let D denote the local calendar date and T the data cutoff's local time. Today covers the start of D through T, with the start of D−1 through T on D−1 as baseline. Last 7 Days covers the start of D−6 through T on D, with the start of D−13 through T on D−7 as baseline. Last 30 Days covers the start of D−29 through T on D, with the start of D−59 through T on D−30 as baseline. Use calendar arithmetic, not fixed 24-hour multiples; baseline windows do not overlap the selected windows. The intentionally unused remainder of the baseline's final day is excluded.
- **Comparison contract:** project summary, provider totals, breakdowns, charts, and differences from one consistent query context containing period, cutoff, time zone, coverage, and pricing revision. Percentage change is the absolute difference divided by a positive baseline only when both periods have sufficient coverage. With confirmed zero baseline and positive current activity, show the absolute increase and No previous usage, with no percentage; confirmed zero in both periods yields No change. With missing history, show known subtotals as Incomplete history and withhold misleading comparisons. A combined comparison requires comparable coverage for both providers and an explicit cutoff; it must not silently mix freshness or assume missing activity is zero.
- **Combined scope:** combined totals sum explicitly labeled tracked tool activity. They do not claim complete account-wide consumption or guaranteed universal matching of requests across sources with different coverage.
- **Estimated Cost contract:** value both providers' consumption at model API rates using one pricing-table revision for the entire query and baseline. Exclude subscription fees and provider billing fields from this valuation. Estimates may be recalculated when rates change; preserve token accounting independently. Reported Cursor charges may be shown separately in details, never added to Codex estimates as if they shared a billing meaning.
- **Pricing catalog:** use the public models.dev catalog as the primary technical source, with validated bundled fallback data and source-dated supplementary rates only where verified. Refresh daily asynchronously, retain the last valid table offline/on failure, and expose its date. Unknown model, cache, context, or tier rates must not receive arbitrary substitutions. Native Cursor model names and aliases require explicit verification. An unknown value remains unpriced, not zero. Display the priced subtotal as Incomplete estimate, identify unpriced activity, and suppress affected cost percentage comparisons.
- **Quota contract:** show quota remaining and provider-reported reset times independently of token history, selected period, and valuation metric. Do not infer token counts from quotas. Account quota data must not relabel device-scoped history.
- **Refresh contract:** run automatic refresh every five minutes while the app is running, including while its panel is closed. Provide manual Refresh; it may bypass local freshness caching but not provider-requested retry delays. Prevent overlapping work per source, bound concurrency, support cancellation, and preserve import checkpoints. One source's failure must not hold back healthy-source publication.
- **Freshness and failures:** preserve last successful values and their original data cutoff, age, and identity. Distinguish disconnected, importing, fresh, stale, access denied, authentication required, incomplete history, and incomplete estimate. A failed request is not a history deletion or successful zero reading. Cached comparisons do not advance merely because time passes. Surface access failures specifically; broad Full Disk Access is not a default prerequisite.
- **Presentation:** use the supplied screenshot's hierarchy and compact visual language, not every behavior in that older product version. Tokens is primary; switching to Cost displays Estimated Cost and changes the main donut and provider values. Offer Today, Last 7 Days, and Last 30 Days. Show absolute/percentage comparisons beside summary/provider results when meaningful. Expand providers for categories, model breakdowns, and hourly Today/daily longer-period charts. Keep quotas independent. Persist metric/period preferences; ensure screen-bounded scrolling, keyboard access, and accessible chart descriptions. Keep sample data in previews and verification rather than normal account presentation.
- **Privacy:** network access is permitted for provider authentication, usage retrieval, and pricing only within feature scope. Keep the ledger local, app-owned credentials in Keychain, and logs free of credentials and conversation content. There is no application backend, cloud sync, or product analytics.
- **Delivery sequence:** prove real collection/access and observed source capabilities first; build durable accounting second; implement aligned comparisons and estimates third; connect the native dashboard fourth; validate real data, restart, recovery, and performance last. If a required capability cannot be established, report the concrete discrepancy before changing product scope.

## Testing Decisions

- The user confirmed four test boundaries: source records through persisted ledger; ledger plus clock and pricing through complete dashboard results; provider lifecycle through authentication/backoff/stale/partial behavior; and native UI smoke checks plus real-data reconciliation.
- Test externally observable accounting and lifecycle behavior, not private helper calls, exact SQL statements, view nesting, timer invocation counts, or implementation-mirroring snapshots. Prefer an existing public seam where it expresses the required behavior. New seams should be at the collector/import, dashboard query, and provider lifecycle boundaries, rather than exposing individual parsing helpers solely for tests.
- Existing prior art is the diagnostics self-check harness: scenario-based rule behavior, open/update/resolve lifecycle checks, and a persistence round trip using an isolated temporary directory. It demonstrates deterministic input-to-result and persistence-boundary testing, but does not validate LLM collection. The inspected Xcode project currently has an application target and no dedicated XCTest target; add a suitable test target/harness for the new integration boundaries rather than treating the old five self-checks as coverage of this MVP.
- **Source-to-ledger tests:** use sanitized usage fixtures with independent expected totals and temporary real SQLite stores. Cover disjoint Cursor buckets, Codex inclusive cached input, unavailable counters, streaming/cumulative updates, duplicate events, copied/forked sessions, append-only growth, file replacement/truncation, repeated imports, full pagination, incomplete pages, malformed records, checkpoint resume, restart, and retention. Repeat imports must not change totals; genuinely new activity must be counted exactly once.
- **Ledger-to-dashboard tests:** seed known activity and query the full presentation result with controlled clocks and time zones. Assert combined/provider/model/category/chart agreement; exact non-overlapping Today/7-day/30-day boundaries; matched-progress baselines; midnight, month/year, and daylight-saving boundaries; cached cutoffs; absolute/percentage differences; confirmed zero; missing coverage; and unequal freshness. Invalid percentages must remain absent rather than appear as zero or infinity.
- **Valuation tests:** use a fixed catalog revision with independently calculated model/cache rates. Verify the same rates are applied across providers and both periods, subscription/billing amounts never enter the estimate, catalog updates can revalue history without changing tokens, unknown/conditional rates mark costs incomplete, and failed catalog refreshes preserve last valid offline rates. Do not validate calculated API-rate value against a subscription invoice as though they should match.
- **Provider-lifecycle tests:** use controlled HTTP/credential/clock boundaries rather than live credentials in automated tests. Exercise Cursor login renewal, rejected authentication, explicit scope, reconnection, Codex login change confirmation, request cancellation, rate-limit retry windows, manual refresh during backoff, unavailable network, failed import, and independent healthy-provider updates. Inspect published identity, freshness, error, and coverage state rather than private scheduling details.
- **Persistence/privacy checks:** reopen the ledger and verify histories, scopes, checkpoints, coverage, and preferences survive. Verify retained metadata/logs do not contain prompt bodies, responses, source code, or tokens used for authentication. Ensure failed reads do not erase known data or establish false zero coverage.
- **Native UI checks:** verify metric and period switching, donut/legend agreement, provider expansion, chart buckets, quota independence, zero/empty/importing/stale/partial/error states, keyboard navigation, readable accessibility summaries, and scrolling on constrained screens. Include long localized numbers and currency formatting so labels do not clip. Visual fixture checks do not replace collection/accounting validation.
- **Real-data acceptance:** connect both real sources, reconcile representative day/model/category totals with source records, and exercise restart plus a subsequent incremental refresh. Where 60 days genuinely exist, verify 30-day comparisons against independently selected baseline records. If source history is unavailable, confirm the explicit unavailable state rather than manufacturing a passing baseline.
- **Performance/build acceptance:** run an appropriate native build and inspect panel responsiveness during initial import and normal refresh. Verify bounded background work, no blocking collection on the main actor, and no redundant full rescan/request storm with the panel open or closed. Numeric performance budgets should follow measured first-pass behavior, not invented thresholds.
- No new LLM implementation or tests have been run as part of this PRD publication. Historical diagnostics self-check and exploratory UI build results do not establish feature acceptance.

## Out of Scope

- Providers other than Cursor and Codex.
- Multiple simultaneously active accounts, account/workspace switchers, or silently merging personal/team histories.
- Guaranteed account-wide Codex history or guaranteed 60-day provider retention when the underlying sources do not supply it.
- Backend services, cloud sync, product analytics, and retaining conversation archives or source code.
- Mac App Store distribution, App Sandbox compatibility work, and broad Full Disk Access as a default requirement.
- Predicted exhaustion times, pace forecasts/warnings, and notifications, even though the visual reference includes them.
- Subscription invoice reconstruction, combined billed-spend totals, custom price editing, and inventing rates for unknown models.
- Project/session drill-down, browsing older history outside the three dashboard periods, and long-term retention beyond 90 days.
- Treating the existing exploratory UI as an approved specification or a completed usage collector.
- Implementing the feature merely because this PRD has been published; implementation requires the user's explicit direction.

## Further Notes

The scope was settled through a planning interview, including an explicit correction that Cost must be selectable in the main view rather than restricted to details. The confirmed testing boundaries are captured above. This PRD preserves that final scope; earlier exploratory behavior must not override it.

Reference implementations were inspected with GitHub CLI at pinned revisions, without live provider-authentication tests:

- [OpenUsage 1acc905](https://github.com/robinebers/openusage/tree/1acc9059b5ac3a6468d501647a151466cdfa024a): useful reference for provider HTTP clients, app-owned authentication, pagination, snapshots, backoff, and stale-data handling. Its current architecture uses provider-reported data rather than native local token scanners.
- [CodexBar 897bff3](https://github.com/steipete/CodexBar/tree/897bff31731bb4b21b105f6e8bf4c32a8a8bf095): useful reference for separating quotas from native local token accounting, incremental/deduplicated scanning, and pricing-cache behavior. Its existing Cursor monetary behavior must not replace the agreed shared-rate valuation.
- [OpenUsage 0.7.16](https://github.com/robinebers/openusage/tree/v0.7.16): visual reference corresponding to the screenshot, including donut, period selection, provider cards, and trends; this differs from current OpenUsage.

Technical validations remain part of initial implementation, not assumptions of feature completeness:

- Cursor supports timestamped paginated date queries in the inspected implementation, but that app currently fetches 30 days and collapses events to daily totals. It does not establish a guaranteed 60-day retention contract. Validate actual historical coverage, complete pagination, app-owned browser login/renewal, exact workspace scoping, and supported quota fields. [Source](https://github.com/robinebers/openusage/blob/1acc9059b5ac3a6468d501647a151466cdfa024a/Sources/OpenUsage/Providers/Cursor/CursorUsageClient.swift#L84-L103).
- CodexBar demonstrates timestamped/hourly local accounting, but available history depends on local transcripts/cache. Validate transcript variants, replay/fork identity, configured-home discovery, and safe quota access. [Source](https://github.com/steipete/CodexBar/blob/897bff31731bb4b21b105f6e8bf4c32a8a8bf095/Sources/CodexBarCore/Vendored/CostUsage/CostUsageScanner%2BTemporalBuckets.swift#L53-L93).
- Current pricing for native Cursor models, aliases, cache discounts, and conditional context/tier rates must be verified. Historical OpenUsage supplements are design evidence, not verified current prices; unsupported activity must remain unpriced. [Historical pricing change](https://github.com/robinebers/openusage/pull/827).
- Verify personal-build signing, retained native API requirements, and resource inclusion. Local exports and unrelated working-tree changes must not be accidentally bundled, overwritten, or committed.

Definition of done: both real sources populate the native dashboard; retained accounting survives restart and reimport; available totals and comparisons reconcile; incomplete/stale/unpriced cases are honest; privacy boundaries hold; and native build, accounting/lifecycle checks, and manual UI/responsiveness checks pass. Source limitations do not authorize fabricated completeness.

Published PRD: [GitHub issue #1](https://github.com/predo-soares/stats/issues/1).
