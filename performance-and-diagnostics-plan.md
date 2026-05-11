# Performance And Diagnostics Plan

## Overview

This plan improves the app in two linked areas:

1. Reduce runtime overhead and UI contention caused by system sampling on the main actor.
2. Add a diagnostics layer that interprets sampled metrics into actionable user-facing issues with recent persisted history.

The plan intentionally excludes the previously proposed menu bar summary enhancement phase.

## Current State Analysis

The app is a macOS menu bar utility with an AppKit shell and SwiftUI content:

- App shell and panel orchestration live in [stats/App/AppDelegate.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/App/AppDelegate.swift).
- The dashboard surface lives in [stats/Features/Dashboard/ContentView.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/Features/Dashboard/ContentView.swift).
- CPU, memory, and disk detail panels live in:
  - [stats/Features/Dashboard/CPUDetailView.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/Features/Dashboard/CPUDetailView.swift)
  - [stats/Features/Dashboard/MemoryDetailView.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/Features/Dashboard/MemoryDetailView.swift)
- All system sampling currently flows through one observable main-actor store in [stats/Stores/SystemStatsStore.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/Stores/SystemStatsStore.swift).
- The shared UI state model lives in [stats/Models/SystemStatsSnapshot.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/Models/SystemStatsSnapshot.swift).

Key findings from code inspection:

- `SystemStatsStore` is `@MainActor`, but it performs expensive sampling work there, including:
  - full process enumeration
  - repeated `proc_pidinfo` calls
  - GPU registry reads
  - SMC temperature reads
- Sampling is already conceptually split by cadence:
  - slower refresh loop every 10s in `refreshTask`
  - faster refresh loop every 1s in `cpuRefreshTask`
- Process-related reads are duplicated across CPU and memory ranking paths.
- The app already supports intervention through process termination, but diagnostics and explanation are minimal.
- The current memory “pressure” field is a usage proxy in [stats/Models/MemoryStats.swift](/Users/pedrosoares/Documents/work/personal/mac-stats/stats/stats/Models/MemoryStats.swift), not a diagnostics-grade pressure signal.

## Desired End State

After this plan:

- expensive system sampling runs off the main actor
- the main actor only publishes coherent UI snapshots
- subsystem cadences are separated so cheap fast metrics are not blocked by slower work
- diagnostics are implemented as a pure Swift domain layer under a dedicated feature boundary
- the dashboard has an always-visible diagnostics area with:
  - `Active Issues`
  - `Recent Issues`
- active issues are actionable, rule-based, and can tap through to existing detail panels
- recent issues persist across restarts using a compact JSON file in app support
- diagnostics are backed by automated tests for rule evaluation, lifecycle handling, and persistence
- shipping requires a final manual performance validation pass

## Agreed Scope And Decisions

The following decisions were resolved during plan review and should be treated as requirements:

- Keep lightweight in-app measurement infrastructure.
- Use separate sampling lanes by cadence and cost.
- Split CPU ticks from top-process sampling cadence.
- Keep a single shared UI snapshot model, published as full snapshot replacement.
- Start diagnostics as rule-based only.
- Diagnostics should include suggested actions from the start.
- Suggested actions should be informational first, with direct controls only through existing safe UI.
- Start with in-app alert states only, not system notifications.
- Persist recent issue history across restarts.
- Persist issue events plus a compact contextual metric snapshot.
- Require sustained conditions over time for issue creation.
- Exclude battery diagnostics from the first diagnostics phase.
- Persist issue events only, not raw long-term metric histories.
- Allow only one active event per surfaced issue at a time.
- Record recovery explicitly.
- Tailor recommendations using top offender processes when available.
- Default to a single top offender, with up to 3 contributors when load is distributed.
- Surface diagnostics directly in the main dashboard.
- Grow the panel vertically rather than replacing existing tiles.
- Keep the diagnostics section always visible.
- Keep the healthy state minimal and quiet.
- Make active issues tappable to open the relevant detail panel.
- Opening the target detail panel is sufficient in v1; no in-panel highlighting required.
- Keep preferences minimal in the first pass.
- Show recent issue history in the UI immediately.
- `Recent Issues` should show resolved issues only.
- `Recent Issues` rows stay compact.
- Allow clearing the full persisted recent issue history store at section level.
- Keep process termination available, but gate it with stronger safety controls and a preference.
- Add a lightweight automated test harness.
- Implement diagnostics as a pure Swift domain layer.
- Add a dedicated `stats/Features/Diagnostics/` boundary.
- Define a narrower diagnostics input model rather than using `SystemStatsSnapshot` directly.
- Keep the diagnostics input mapper inside the diagnostics feature.
- Run diagnostics on every relevant sample publish.
- Merge related signals in a composition layer after independent rule evaluation.
- Keep merge policy explicit and hardcoded initially.
- Use dynamic severity per rule rather than fixed global severities.
- Key issue identity by surfaced user-facing issue type.
- Keep an issue open when contributors change but the surfaced type is unchanged.
- Resolve and reopen when the surfaced issue type changes.
- Use both absolute and percentage thresholds for low disk.
- Refine memory diagnostics input before trusting current memory-usage proxy.
- Distinguish foreground-app load from background/system load before recommending CPU actions.
- Use simple heuristics for process classification in v1.
- Keep dashboard recommendations soft; do not suggest process kill directly from diagnostics text.
- Persist exact relevant process names in issue context.
- Write history to disk immediately on issue lifecycle changes.
- Show up to 3 active issues in a vertical list.
- Sort active issues by severity first, then actionability, then recency.
- Require a dedicated final manual performance-validation pass before enabling diagnostics by default.

## Non-Goals

This plan does not include:

- system notifications in the first diagnostics release
- per-rule threshold customization UI
- persisted long-term raw telemetry storage
- ML or LLM-generated explanations
- new detail panels beyond CPU, memory, and disk
- exact in-panel evidence highlighting when opening detail views
- battery diagnostics in the first rule set
- a database-backed persistence layer
- broad menu bar feature redesign

## Implementation Approach

### Architectural Direction

Keep the UI’s existing high-level shape intact:

- `SystemStatsStore` remains the app-facing observable coordinator.
- `SystemStatsSnapshot` remains the coherent state model consumed by SwiftUI.
- expensive sampling work moves into background-capable subsystem samplers or worker paths
- a coordinator composes fresh subsystem outputs into a new full snapshot
- diagnostics consume a narrower derived input model, not the raw UI snapshot directly

### New Boundary

Add a dedicated diagnostics feature area:

- `stats/Features/Diagnostics/Models/`
- `stats/Features/Diagnostics/Rules/`
- `stats/Features/Diagnostics/Persistence/`
- `stats/Features/Diagnostics/Presentation/` if adapters are needed

Exact file splits can be adapted during implementation, but the diagnostics domain should not be folded into `Stores` or general `Models`.

## Phases

### Phase 1: Baseline And Instrumentation

Goal: create a lightweight performance baseline and internal measurement hooks that remain useful throughout implementation.

Changes:

- add internal timing and sampling counters for:
  - subsystem sample durations
  - snapshot publish duration
  - process enumeration cost
  - panel open/render timing where practical
  - skipped, delayed, or overlapping refresh detection
- expose instrumentation in a debug-friendly way without requiring a broad UI surface
- document baseline metrics to compare before and after refactors

Implementation notes:

- keep instrumentation lightweight and local
- avoid turning instrumentation into a user-facing feature in this phase
- prioritize data needed to validate future sampling changes

Risks:

- overbuilding observability instead of collecting only decision-useful measurements

### Phase 2: Sampling Architecture Refactor

Goal: move expensive sampling work off the main actor while preserving a single coherent UI snapshot.

Changes:

- split sampling into three lanes:
  - startup lane: hardware and model discovery
  - fast lane: CPU ticks
  - slower lanes for process rankings and slower subsystem metrics
- move raw sampling operations out of the main-actor hot path
- keep main-actor responsibilities limited to:
  - holding latest results
  - composing full snapshot replacements
  - publishing observable state to SwiftUI

Cadence targets:

- CPU ticks: every 1s
- top CPU processes: every 3s
- top memory processes: every 10s
- memory, disk, battery, network: every 10s
- hardware discovery: startup only, with no repeated shell-out loop

Implementation notes:

- preserve `SystemStatsSnapshot` as the UI contract
- do not introduce partial field mutation semantics into views
- ensure background work does not race snapshot publication

Risks:

- introducing inconsistent snapshots if subsystem updates are published directly
- changing thread affinity around IOKit, Mach, and AppKit-dependent code without guarding boundaries

### Phase 3: Process Sampling Consolidation And Metric Refinement

Goal: reduce redundant work and prepare diagnostics-grade inputs.

Changes:

- consolidate duplicated process walks used by:
  - top CPU processes
  - top memory processes
- centralize process sample derivation so one enumeration can feed multiple rankings
- refine memory diagnostics inputs beyond the current `used / total` proxy
- separate UI-friendly memory display values from diagnostics-grade memory signals

Memory refinement scope:

- include available headroom
- include compressed memory
- include swap usage
- include swap growth over time
- include true pressure-like signals where practical and reliable

Implementation notes:

- this phase is a prerequisite for trustworthy memory issue rules
- the UI may still continue displaying current memory usage concepts, but diagnostics should not rely on a naive proxy

Risks:

- regressions in process ranking freshness
- unclear separation between display metrics and decision metrics

### Phase 4: Diagnostics Domain And Rule Engine

Goal: add a pure Swift diagnostics system that evaluates system state on every relevant sample publish.

Changes:

- add diagnostics domain models:
  - diagnostics input
  - rule outputs
  - surfaced issues
  - issue lifecycle state
  - contextual snapshot payload
- add a diagnostics input mapper inside the diagnostics feature boundary
- implement independent rules first, then explicit composition/merge logic
- evaluate rules on every relevant publish

Initial issue families:

- `system_under_heavy_load`
  - merged from high CPU plus thermal stress when applicable
- `memory_pressure`
  - merged from pressure-like memory stress and swap growth
- `low_disk_space`
  - standalone rule using absolute and percentage thresholds

Rule behavior:

- sustained windows are rule-specific
- severity is dynamic within each rule
- surfaced issue ids are keyed by user-facing issue type
- same surfaced issue type updates in place
- changing surfaced issue type resolves old event and opens new event

CPU recommendation logic:

- distinguish dominant user-app load from distributed or system/background load
- use simple heuristics first, not a curated classification table
- diagnostic copy remains soft and advisory

Risks:

- merge logic obscuring why an issue exists if raw contributors are not retained
- noisy issue behavior if sustained windows are too short

### Phase 5: Persistence, Lifecycle, And Dashboard Diagnostics UI

Goal: persist issue history and expose active/resolved diagnostics in the main dashboard.

Changes:

- persist issue lifecycle events to a versioned JSON file in app support
- write immediately on issue lifecycle changes
- cap retained history aggressively
- store:
  - issue id
  - timestamps
  - status
  - severity
  - title
  - suggested action
  - contributing rule ids
  - compact contextual metric snapshot
  - exact relevant offender process names
- record recovery explicitly with `resolvedAt`

Dashboard UI changes:

- add an always-visible `Active Issues` section near the top of the main panel
- add a healthy default state when there are no active issues
- display up to 3 active issues, ordered by:
  - severity
  - actionability
  - recency
- make issue rows tappable only when they map to an existing detail panel
- add `Recent Issues` below diagnostics summary
- `Recent Issues` shows resolved issues only
- rows stay compact and one-line summary oriented
- add section-level clear action that wipes the full persisted recent-history store

Implementation notes:

- keep raw rolling histories session-only
- do not add notifications in this phase
- avoid adding a separate history screen until the dashboard version proves useful

Risks:

- panel height growth causing layout regressions or awkward overflow
- ambiguity around clearing history unless active and resolved data are clearly separated

### Phase 6: Safety Controls, Preferences, And Final Validation

Goal: tighten intervention behavior, keep preferences minimal, and verify the app does not become the performance problem.

Changes:

- keep process termination available in detail views
- strengthen confirmation language around process termination
- add a minimal preference or safety control to disable or hide termination actions entirely
- add only minimal settings needed for first release behavior
- avoid exposing per-rule tuning UI yet

Final validation scope:

- confirm sampling overhead is acceptable at idle
- confirm no visible UI hitching when panel opens
- confirm CPU chart remains smooth
- confirm diagnostics open and resolve as expected
- confirm persisted history survives relaunch
- confirm history clearing behavior is exact and understandable
- confirm no alert spam or premature issue creation during realistic usage

Risks:

- under-specifying safety behavior around process actions
- releasing diagnostics before thresholds feel trustworthy in real-world usage

## Testing Strategy

### Automated Verification

- add unit tests for diagnostics rule evaluation:
  - brief spikes do not create issues
  - sustained conditions do create issues
  - severity escalation behaves as expected
- add lifecycle tests:
  - one active issue per surfaced issue type
  - contributors can change without reopening
  - surfaced type changes resolve and reopen correctly
  - recovery is recorded explicitly
- add merge/composition tests:
  - high CPU plus thermal stress merges correctly
  - memory pressure plus swap growth merges correctly
  - low disk remains standalone
- add persistence tests:
  - JSON encode/decode round-trip
  - retention cap behavior
  - immediate write path
  - clear-history behavior
- add diagnostics input mapper tests:
  - expected normalized inputs are derived from sampled state
- run existing project build validation after each major phase

Suggested verification commands should be adapted to the local project once final build/test commands are confirmed, but at minimum include:

```sh
xcodebuild -scheme stats -project stats.xcodeproj -configuration Debug build
```

If test targets are added during implementation, extend verification with the corresponding `xcodebuild test` invocation.

### Manual Verification

- open the main panel repeatedly and confirm responsiveness
- verify the panel height adjustment after diagnostics/history sections are added
- verify healthy-state dashboard rendering
- verify degraded-state rendering with 1, 2, and 3 active issues
- verify tap-through from issue rows to CPU, memory, and disk detail panels
- verify process termination confirmation copy and disable/hide preference behavior
- verify recent issue persistence across app relaunch
- verify clear-history behavior removes resolved history and preserves active issue state
- verify issue durations and recovery timestamps make sense in realistic runs
- validate idle overhead and responsiveness under CPU, memory, and disk pressure scenarios

## Migration And Rollout Notes

- No external data migration is required before diagnostics persistence is introduced.
- The persisted issue-history file should be versioned from the first implementation to allow future schema evolution.
- Diagnostics should remain conservative until manual performance validation confirms acceptable behavior.
- If issue quality is uncertain late in implementation, prefer shipping the diagnostics engine and persistence behind a minimal internal gating path rather than exposing noisy issue summaries by default.

## Open Implementation Considerations

These are implementation considerations, not blockers:

- whether to represent sampling workers as dedicated helper types or private store-owned subsystems
- exact file subdivision under `stats/Features/Diagnostics/`
- exact thresholds after baseline instrumentation confirms realistic system behavior
- whether to expose instrumentation only in logs/debug UI or also in a developer-only panel

## Recommended Execution Order

1. Phase 1: baseline and instrumentation
2. Phase 2: sampling architecture refactor
3. Phase 3: process consolidation and metric refinement
4. Phase 4: diagnostics domain and rule engine
5. Phase 5: persistence and dashboard diagnostics UI
6. Phase 6: safety controls, preferences, and final validation

This ordering keeps performance work ahead of feature work, and keeps diagnostics logic ahead of persistence/UI rollout.
