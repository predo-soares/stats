# OpenUsage Cursor and customization research

Inspected through GitHub CLI on 2026-11-04. Upstream main revision: `596ca1041dc87f2c97881f46b109f563e341c8b8`.

## Authentication and requests

`AccountProviderRuntime.refreshCursor` resolves OAuth credentials, reads GetCurrentPeriodUsage using a bearer token, renews once on an authentication failure, then maps the response. `AccountProviderRuntime+CursorAuth` renews a week before JWT expiry, retains a still-valid token after early renewal failure, and persists the new token. The replacement access token becomes the next refresh token when the server omits one.

`CursorUsageClient.session` derives the cookie prefix from the current JWT subject. Dashboard GET and event POST requests use this cookie. Event POSTs include Origin and millisecond string bounds. The API2 quota calls use bearer authentication and Connect-Protocol-Version: 1.

## Independent quota and token history

`AccountProviderRuntime+CursorUsage` begins history asynchronously while mapping quota data. GetPlanInfo supplies the plan name; usage-summary membership and response shape determine request-based, personal, or organization fallback behavior. Legacy request counts, credits and prepaid balance are separate observations. Quotas cannot supply daily token totals.

`CursorHistorySource` reads individual local calendar days with four concurrent requests and a twenty-second budget. It accepts only complete pagination with consistent counts and events inside the requested day. Successful days survive failures of other days. Rate limiting stops the pass and supplies the next retry delay.

`CursorUsageEvents.parsePage` requires totalUsageEventsCount. A missing event array is permitted when a count is present. Literal `{}` is rejected. The previous claim that OpenUsage accepts `{}` as confirmed empty was incorrect; CodexBar has that behavior. An empty object observed in our live probe therefore establishes only that the endpoint returned no usable event fields, not that the account had no activity.

Tokens sum input, cache read, cache write and output. Missing tokenUsage counts as zero for that event. Charged cents are handled separately and only qualifying chargeable on-demand events contribute reported charges.

## Customization

`LayoutStore` persists hiddenMetricIDs. setMetric changes visibility and removes hidden metrics from priority pins. `LayoutStore+Customization.displayGroups` filters descriptors using isMetricShown. These controls are display preferences, not collection consent switches. Collection and underlying accounting remain separate.

## Local gaps found

- Cursor quota was computed before events but returned only after events and all historical work succeeded. An event error discarded the successful quota publication, leaving the initial not-connected message.
- Our history collector has four concurrent days but lacks OpenUsage's persisted completed-day state, total deadline and rate-limit retry policy. It rereads the historical window on refresh.
- Our empty-object parser follows CodexBar, not OpenUsage. No runtime evidence yet establishes whether this Cursor account has current timestamped usage. Do not infer account inactivity from `{}` alone.
- Current quota mapping covers personal percentages and legacy request counts; it does not yet implement all enterprise/shared-pool, unified billing, credit and prepaid branches.
- Plan labels in the cards are currently fixed strings, not verified subscription metadata.

## Sources

All paths below are relative to https://github.com/robinebers/openusage/tree/596ca1041dc87f2c97881f46b109f563e341c8b8

- Sources/OpenUsage/Providers/AccountProviderRuntime.swift
- Sources/OpenUsage/Providers/Cursor/AccountProviderRuntime+CursorAuth.swift
- Sources/OpenUsage/Providers/Cursor/AccountProviderRuntime+CursorUsage.swift
- Sources/OpenUsage/Providers/Cursor/CursorUsageClient.swift
- Sources/OpenUsage/Providers/Cursor/CursorHistorySource.swift
- Sources/OpenUsage/Providers/Cursor/CursorUsageEvents.swift
- Sources/OpenUsage/Providers/Cursor/CursorUsageMapper.swift
- Sources/OpenUsage/Providers/Cursor/CursorUsageSummaryMapper.swift
- Sources/OpenUsage/Stores/LayoutStore.swift
- Sources/OpenUsage/Stores/LayoutStore+Customization.swift
