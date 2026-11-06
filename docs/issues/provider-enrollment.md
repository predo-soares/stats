 # S1 — Enroll providers with visual support states

## What to build

Deliver a skippable first-launch provider enrollment flow and the corresponding Settings path. It presents providers with visual support states, persists the user's selection, and keeps collection/privacy disclosure plus connection actions in provider details. Supported providers remain unbadged; experimental and detected providers use colored icons with native tooltips.

## Acceptance criteria

- [ ] A first launch can select providers or finish with none selected; choices persist and are editable in Settings.
- [ ] Provider details, not onboarding, explain collection/privacy boundaries and expose connection actions.
- [ ] Experimental and detected states have distinct color/icon indicators and native tooltips; supported has no badge.
- [ ] Source-evidence access and per-provider unavailable states remain usable from Settings.
- [ ] Automated lifecycle and native UI checks cover selection, skip, persistence, tooltip semantics, and keyboard access.

## Blocked by

None - can start immediately.

## Implementation notes

### Implemented
- `ProviderSupportState` with Supported (no badge), Experimental, and Detected color-only icons + native tooltips.
- `ProviderEnrollmentStore` + `ProviderCatalog` persisting first-launch selection independently of credentials; Skip finishes with none selected.
- Skippable `ProviderEnrollmentView` shown on first launch from `AppDelegate`; returning installs with prior usage/connection keys migrate without re-prompting.
- Settings Connections list and detail show support-state indicators; collection/privacy disclosure and connection actions live only in provider detail.
- Source evidence diagnostics remain reachable from Settings; paused/unavailable provider messages surface per provider.
- Dashboard provider headers render support-state indicators.

### Decisions
- Codex and Cursor remain Supported; Experimental/Detected presentation is shared for later adapters.
- Fresh installs default connections to off until enrollment completes; legacy installs keep prior connection state.
- Enrollment enable flags stay mirrored to existing `usage.connection.*` keys so refresh lifecycle is unchanged.

### Verification
- `scripts/run_provider_enrollment_self_checks.swift` → PASS (support semantics, persistence, skip, legacy migration, catalog, privacy copy).
- `xcodebuild -project stats.xcodeproj -scheme stats -configuration Debug build -derivedDataPath .build-run` → BUILD SUCCEEDED.

### Limitations
- Experimental providers are not yet in the enrollable catalog (arrive in later slices).
- Native UI keyboard paths covered via SwiftUI shortcuts/accessibility traits; no XCTest UI harness exists.

### Commit
`aff43bd`

## Cursor delegation prompt

Implement local slice S1. Build the skippable provider-enrollment flow and Settings state indicators described above. Read the local PRD, glossary, ADRs, and this document first; preserve unrelated WIP. You may spawn subagents for independent UI or fixture work, but own integration. Run the native build and focused UI/lifecycle checks, update this document's Implementation notes with the commit and verification, then create one focused commit for S1.
