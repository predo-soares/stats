## Problem Statement

The app currently focuses on Cursor and Codex, but Cursor token history is demonstrably incomplete for the active account and other providers cannot all be validated against paid subscriptions. Pedro still needs a trustworthy way to opt into additional local LLM sources, beginning with Pi, without treating a source discovery as proof of reliable token consumption, exposing private session content, or double-counting activity routed through multiple providers.

## Solution

Add a provider-adapter foundation and first-launch provider enrollment. Users choose which providers to enable; detailed collection/privacy disclosure and connection controls remain in each provider detail screen. Pi is the first runtime adapter, importing only local Pi session metadata and preserving underlying provider/model provenance. Provider capability is communicated visually: supported providers are unbadged; experimental and detected providers use colored icons with native tooltips. All unvalidated adapters use sanitized contract fixtures based on observed OpenUsage, T3 Code, and CodexBar behavior and remain Experimental until real-account reconciliation.

## User Stories

1. As a new user, I want to select which providers to enable during first launch, so that the app collects only sources I chose.
2. As a new user, I want to skip provider setup, so that I can configure sources later.
3. As a returning user, I want my selected providers to remain enabled after relaunch, so that setup is not repeated.
4. As a user, I want to change provider selection in Settings, so that I can pause, re-enable, or remove a connection.
5. As a user, I want provider details to explain what is collected and never retained, so that I can make an informed connection decision.
6. As a user, I want onboarding to remain focused on selection, so that privacy detail does not obstruct first use.
7. As a user, I want supported providers to appear without a status badge, so that established connections stay visually quiet.
8. As a user, I want experimental and detected providers represented by color-only icons with tooltips, so that I can understand source reliability without clutter.
9. As a user, I want Pi to be selectable as a provider, so that I can track LLM activity performed through Pi.
10. As a Pi user, I want local session metadata imported without provider API keys, so that tracking works from the sessions already on my Mac.
11. As a Pi user, I want Pi token consumption kept separate from direct provider totals, so that the same activity is not silently counted twice.
12. As a Pi user, I want the underlying model and provider retained when available, so that I can understand what Pi routed my activity to.
13. As a Pi user, I want Pi records retained for 90 days, so that recent history survives relaunches.
14. As a privacy-conscious user, I want prompts, responses, tool arguments, source paths, credentials, and raw session payloads excluded from the ledger, so that usage tracking does not become an archive.
15. As a user, I want Pi totals shown even when a model cannot be priced, so that unknown rates do not hide token consumption.
16. As a user, I want unpriced Pi activity to mark estimated cost incomplete, so that an invented cost is never displayed.
17. As a user, I want source discovery to remain distinct from source support, so that finding a local directory is not presented as valid accounting.
18. As a user, I want an unavailable source to preserve known local history and show its state, so that a missing runtime does not erase data.
19. As a user, I want adapter errors to be source-specific, so that a Pi parsing failure does not prevent Codex or Cursor updates.
20. As a user, I want a redacted source-evidence report, so that I can inspect coverage without exposing sensitive content.
21. As a user, I want incomplete Cursor history excluded from combined token and cost comparisons, so that the dashboard remains honest while Cursor investigation continues.
22. As an evaluator, I want experimental adapters backed by deterministic fixtures, so that their behavior can be tested without paid subscriptions.
23. As an evaluator, I want a provider promoted to Supported only after real-source reconciliation, so that support status has a meaningful standard.
24. As a user, I want provider cards and the combined total to state incomplete coverage instead of showing fabricated zeros, so that decisions are based on known data.
25. As a user, I want the existing native menu-bar workflow to remain responsive during local discovery and import, so that enabling a provider does not block the dashboard.

## Implementation Decisions

- Add a provider-adapter contract separating local availability probing, enrollment, collection, normalization, provenance, support state, and presentation. A detected source is not an enabled or supported source.
- Persist provider enrollment independently from credentials. First launch shows only provider choices and support-state indicators; users may skip. Provider detail settings contain collection/privacy disclosure and the connection action.
- Keep supported providers unbadged. Experimental and detected providers use distinct colored icons with native tooltips; do not add status text to the compact list.
- Implement Pi first as a runtime source using local Pi session logs. Store only timestamp, token categories, model, underlying provider, safe source identity, and import metadata. Retain 90 days.
- Keep Pi as an independent provider card and total. Preserve model/provider provenance, but exclude Pi activity from direct-provider totals and from any combined total that could overlap until cross-source duplicate identity is proven.
- Reuse the existing SQLite ledger, coverage model, token/cost query path, provider lifecycle state, settings detail presentation, and diagnostics presentation. Extend them to retain source kind, runtime/provider provenance, enrollment, and support state without storing raw session payloads.
- Keep estimated cost independent from token accounting. Unknown Pi model pricing produces an incomplete estimate and never a substituted zero or guessed rate.
- Treat Cursor source evidence as a release gate: retain known subtotals, label stale history incomplete, and exclude incomplete Cursor history from combined totals/comparisons while preserving independent quota collection.
- Build fixtures from the publicly observed source contracts in OpenUsage, T3 Code, and CodexBar. Fixtures are contract hypotheses, not proof of present provider behavior. The only promotion path from Experimental to Supported is a redacted real-source reconciliation.
- Subsequent adapters are ordered Claude, xAI Grok, Z.ai, and Antigravity after Pi. They begin Experimental unless a source contract is reconciled.

## Testing Decisions

- Test externally visible collection, persistence, source state, and dashboard results; do not test SQL strings, private scheduling, or view hierarchy.
- Adapter-to-ledger tests use sanitized contract fixtures modeled on observed OpenUsage, T3 Code, and CodexBar formats. They verify normalization, provenance, duplicate handling, 90-day retention, and exclusion of prompts, responses, tool arguments, source paths, credentials, and raw payloads.
- Ledger-to-dashboard tests seed provider/runtime records through the public ledger boundary and verify Pi’s independent totals, incomplete cost behavior, support-state visibility, and absence of cross-source double counting.
- Onboarding-to-settings tests verify selection persistence, skipping onboarding, later setup, enable/disable behavior, and that detailed privacy disclosure is shown only in provider details.
- Provider-lifecycle tests verify detected/experimental/supported transitions, missing local sources, per-source failure isolation, tooltip semantics, and preservation of prior known data.
- Native UI smoke checks cover first-launch selection, compact provider list icon states, provider detail disclosure, keyboard behavior, and constrained menu-panel layout.
- Real reconciliation is manual and optional for each provider. Until it occurs, fixtures validate only the adapter contract and the provider remains Experimental.
- Reuse the existing source-evidence, ledger, period-query, and native build seams. Add only high-level adapter and onboarding seams where the current Cursor/Codex-only model has no applicable public boundary.

## Out of Scope

- Claiming real-provider validation, accurate quota data, or complete token history for providers without a reconciled account.
- Importing browser cookies, decrypting another application's stored tokens, or reading credentials other than explicitly connected app-owned credentials and approved read-only local sources.
- Automatically merging Pi activity into Claude, xAI Grok, Z.ai, or any other provider total.
- Cloud sync, backend services, product analytics, conversation archives, or retention beyond 90 days.
- Recovering the retired business Cursor account.
- Replacing the Cursor source-evidence investigation with a new provider implementation.

## Further Notes

This PRD extends the original Cursor/Codex MVP without changing its measurement vocabulary: token consumption, quota remaining, reported charge, and estimated cost remain separate. Cursor source evidence is a blocking correctness concern, not a reason to fabricate current token totals. The ADR for runtime provenance governs Pi accounting and provider enrollment. The user approved fixture-based validation for providers without paid subscriptions, with explicit Experimental status until real reconciliation.

