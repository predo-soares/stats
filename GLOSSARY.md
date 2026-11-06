# LLM Usage Tracking

Personal tracking of Cursor and Codex consumption. Token consumption, subscription quotas, and money are separate measurements.

## Language

**Token consumption**:
The number of tokens consumed by LLM activity, distinguished by the token categories reported by its source.
_Avoid_: Spend, quota usage

**Quota remaining**:
The unused portion of an account's allowance within a provider-defined limit window. It is not a token count or a monetary balance.
_Avoid_: Tokens remaining, budget remaining

**Reported charge**:
A monetary charge reported by the service for usage. It is distinct from a calculated API-rate estimate and a subscription fee.
_Avoid_: Estimated cost

**Estimated cost**:
A calculated API-rate value of token consumption using model pricing, excluding subscription fees. It does not establish what the user was billed; the same meaning applies to Cursor, Codex, and their combined estimate.
_Avoid_: Reported charge, actual spend

**Coverage**:
The activity included in a measurement, such as locally available Codex sessions or provider-reported Cursor account activity. Totals with different coverage are not equivalent views of the same activity.

**Usage ledger**:
A retained history of consumption metadata and accounting identifiers, excluding conversation content and source code.
_Avoid_: Conversation archive

**Local device activity**:
Usage recorded in locally available sessions on the monitored Mac, potentially spanning multiple logins. It does not by itself establish which account owns that consumption.

**Previous-period comparison**:
A comparison of token consumption in a selected period with the preceding equivalent period, aligned to the same elapsed portion. Its time boundaries and data coverage must be explicit.

**Last 7 Days**:
Today and the preceding six calendar days in the Mac's local time zone, through the current time. Its baseline is the preceding seven-day window through the matching local time on that window's final day.

**Last 30 Days**:
Today and the preceding 29 calendar days in the Mac's local time zone, through the current time. Its baseline is the preceding thirty-day window through the matching local time on that window's final day.

**Data cutoff**:
The latest activity time represented by a displayed measurement. A cached comparison retains its original cutoff rather than advancing with the clock.

**Incomplete history**:
A consumption result whose required activity coverage has not been established. Its known subtotal is not a complete period total or evidence that missing activity was zero.

**Incomplete estimate**:
A monetary result in which some known consumption lacks reliable pricing. Its priced subtotal excludes unknown value while the underlying token consumption remains recorded.

**Pricing table**:
A dated set of model API rates used to value consumption. One revision applies to both sides of a comparison.

**Workspace**:
A personal or team usage scope selected within the connected Cursor account. Its history is kept separate from other workspaces.

**Provider support state**:
The reliability classification for a provider source. Supported is reconciled against a real account and has no status badge. Experimental has fixture/contract coverage but no real-account reconciliation; show its colored status icon with a native tooltip. Detected means a local source was found but a usable token contract has not been established; show its colored status icon with a native tooltip.
_Avoid_: Available, connected

**Runtime source**:
A client that records LLM activity but may route to multiple underlying providers. Pi is a runtime source: it keeps its own token total and retains underlying model/provider provenance. Its records are excluded from combined provider totals until cross-source duplicate accounting is proven.

**Source evidence**:
A redacted diagnostic summary of a source request and retained ledger state: requested time window, outcome, event count, token subtotal, timestamp bounds, coverage, and safe error reason. It excludes credentials, prompts, code, raw payloads, and event identities.

**Provider enrollment**:
A first-launch selection of which provider connections the user wants enabled. Onboarding shows only provider choices and support-state indicators; collection/privacy disclosure and connection controls live in the provider detail settings screen. Enrollment can be skipped and changed later in Settings.
