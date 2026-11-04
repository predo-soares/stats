# Usage dashboard view refactor

## Goal

Reduce `UsageDashboardView` to dashboard composition and lifecycle wiring. Extract the repeated provider-card layout so Codex and Cursor keep their distinct source states while sharing one visual implementation.

## Current state

`stats/Features/Usage/Views/UsageDashboardView.swift` owns the dashboard layout, summary, both provider cards, quota bars, expandable details, comparison indicators, footer, and period picker. The Codex and Cursor cards duplicate the card shell, hover affordance, quota window layout, expansion behavior, token rows, model breakdown, and trend chart.

The app already separates usage domain code into `Models`, `Services`, and `Persistence`. This refactor stays inside the presentation layer except for one view-facing presentation model.

## Desired end state

`UsageDashboardView` owns only:

- metric and period bindings;
- dashboard refresh lifecycle;
- composition of summary, Codex, Cursor, and footer modules.

Reusable modules own their visual behavior:

- `UsagePeriodPicker` owns its animated indicator and accessibility behavior.
- `UsageComparisonIndicator` owns outcome formatting, color, icon, and tooltip.
- `UsageQuotaWindow` owns the exact quota-bar geometry and reset presentation.
- `UsageSummaryCard` owns the donut, legends, metric menu, and period control.
- `ProviderUsageCard` owns the shared card chrome, hover overlay, expansion, quota rows, and detail layout.

Codex- and Cursor-specific state is adapted before it reaches `ProviderUsageCard`. The shared card does not know about browser sign-in, Codex authentication, workspace storage, or provider client types.

## Non-goals

- Change collection, ledger, pricing, comparison arithmetic, or quota semantics.
- Change the distinction between token consumption, quota remaining, and estimated cost.
- Alter provider copy, refresh behavior, animations, or visual values while extracting code.
- Add new account or workspace controls.

## Phases

### 1. Extract presentation primitives

Move the period picker, comparison indicator, quota window, provider header, and footer into focused view files. Retain current animations, tooltips, spacing, and bar height.

### 2. Extract the summary card

Move donut rendering, metric selection, legends, cost state, and period selection into `UsageSummaryCard`. The dashboard provides values and bindings only.

### 3. Introduce the shared provider-card module

Create `ProviderCardPresentation` with provider identity, plan, header message, quota windows, detail rows, model totals, trend, and status message. Adapt Codex and Cursor state in the dashboard or a dedicated presentation adapter, then render both through `ProviderUsageCard`.

## Verification

### Automated Verification

- Run `xcodebuild -scheme stats -project stats.xcodeproj -configuration Debug build` after every phase.
- Run `git diff --cached --check` before every commit.
- Confirm active source files do not import the legacy system-stats tree.

### Manual Verification

- Open the menu-bar panel and verify metric and period selection still update the summary.
- Verify Codex and Cursor cards expand, collapse, and show the hover-only `View more` affordance.
- Verify quota bars keep their current height, remaining percentage, and reset time.
- Verify unavailable comparison states still show `--` and expose the native comparison tooltip.
- Verify Codex and Cursor connection/error messages remain provider-specific.

## Risks

- A generic card with provider-specific conditional branches would be a shallow module. Keep provider-specific source/authentication mapping outside the card.
- The Xcode project synchronizes the `stats` source tree. New view files under `stats/Features/Usage/Views` compile automatically, so each phase must build before committing.
- Current local quota visual tuning is uncommitted. Preserve it while relocating its implementation and do not discard unrelated working-tree changes.
