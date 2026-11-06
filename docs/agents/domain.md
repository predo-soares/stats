# Domain documentation

This repository has one domain context: personal Cursor and Codex usage tracking.

Before planning or changing the feature:

1. Read the root `GLOSSARY.md` and use its terms. Token consumption, quota remaining, reported charges, and estimated cost are distinct.
2. Read the relevant PRD under `docs/prd/` and its linked tracker issue, including later comments or amendments. `docs/mvp-plan.md` preserves the discovery decisions and research evidence.
3. Read relevant decisions under `docs/adr/`. The shared API-rate valuation decision governs combined costs and previous-period comparisons.

If a CONTEXT.md or context map is introduced later, read it for domain structure; its current absence does not block work. Do not create parallel definitions that contradict the existing glossary.

Surface conflicting specifications or ADRs before changing their meaning. An exploratory UI is not evidence that its fixtures, defaults, or behavior were approved. Preserve unrelated working-tree changes.
