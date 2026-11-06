# Provider local-source contract hypotheses (sanitized fixtures)

Research note for Experimental provider adapters (S2, S4, S6–S8). Fixtures model **observed public contracts** from [OpenUsage](https://openusage.sh/), [CodexBar](https://github.com/steipete/CodexBar), and [T3 Code](https://github.com/pingdotgg/t3code). They are **contract hypotheses**, not proof of current vendor behavior or of this Mac’s on-disk layout.

**Fixture files:** `stats/Features/Usage/Fixtures/*.fixture.{json,jsonl}`

---

## Cross-cutting privacy boundary

| Retain (normalized ledger / tests) | Never retain |
| --- | --- |
| ISO8601 or epoch **timestamp** | **Prompts**, user/assistant **message text**, thinking text |
| Token buckets: input, output, cache read/create, reasoning (when split) | **Tool names/args/results**, file paths from tool I/O |
| **Model** id (and **underlying provider** for runtimes) | Real **home paths**, emails, org/team IDs, session titles |
| Opaque **session / message / request** ids (synthetic in fixtures) | **Credentials**, API keys, OAuth tokens, cookies |
| Optional **reported cost** or quota **percentages** (mark pricing incomplete when unknown) | Full **raw API envelopes** in the ledger (fixtures may hold minimal API slices for parser tests only) |
| Import **metadata**: provider kind, support state, source kind (`local-transcript`, `local-signals`, `api-quota`, `status-line`) | `auth.json`, `.credentials.json`, keychain payloads |

---

## 1. Claude (local activity)

### Likely surface (hypothesis)

| Source | Path / API | Notes |
| --- | --- | --- |
| **Primary (hypothesis)** | `$CLAUDE_CONFIG_DIR/projects/**/*.jsonl` (default `~/.claude/projects/`) | Per-turn transcript; authoritative for tokens ([OpenUsage Claude Code](https://openusage.sh/docs/providers/claude-code/)). |
| Rollups (optional) | `stats-cache.json` / `stats.json` under Claude config dir | Daily aggregates; not required for token ledger tests. |
| T3 / stats alignment | Same JSONL tree; parser expects `type: "assistant"` lines ([T3 `claudeUsage.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Drivers/claudeUsage.ts)) | Dedupe by `(message.id, requestId)` because each content block repeats the same `usage`. |
| CodexBar | Claude strategies include CLI PTY + local logs ([providers.md](https://github.com/steipete/CodexBar/blob/main/docs/providers.md)) | Confirms local JSONL as a first-class path, not API-only. |

### Sanitized fixture field set

- `type`, `timestamp`, `sessionId`, `requestId`
- `message.id`, `message.model`, `message.usage.{input_tokens, output_tokens, cache_read_input_tokens, cache_creation_input_tokens}`
- Optional `costUSD` (estimate only)
- Skip model `<synthetic>` (local placeholder; T3 convention)

### Suggested test schema (JSONL)

One line per assistant turn (after privacy filter):

```json
{"provider":"claude","timestamp":"2026-11-01T15:04:05.123Z","sessionId":"sess-claude-fake-001","requestId":"req-fake-001","messageId":"msg-fake-001","model":"claude-sonnet-4-20250514","inputTokens":1200,"cachedInputTokens":8000,"cacheCreationTokens":0,"outputTokens":340}
```

### Confidence

**High** for JSONL location and assistant `usage` field names (OpenUsage docs + T3 parser). **Medium** for optional `costUSD` and advisor `usage.iterations` (present in newer Claude Code builds).

**Links:** [Claude Code provider](https://openusage.sh/docs/providers/claude-code/), [Paths / env (`CLAUDE_SETTINGS_FILE`)](https://openusage.sh/docs/reference/env-vars/), [T3 usage contract](https://github.com/pingdotgg/t3code/blob/main/packages/contracts/src/usage.ts)

---

## 2. Pi (runtime + underlying provider provenance)

### Likely surface (hypothesis)

| Source | Path | Notes |
| --- | --- | --- |
| **Primary** | `~/.pi/agent/sessions/**/*.jsonl` (override: `sessions_dir` / `PI_CODING_AGENT_SESSION_DIR`) | [OpenUsage Pi](https://openusage.sh/docs/providers/pi/) |
| Oh My Pi | `~/.omp/agent/sessions/` | Same transcript shape; dedupe by canonical path in OpenUsage. |
| T3 | Same tree; [`piUsage.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/provider-pi/src/server/usage.ts) | Parses `session` header + `message` / `usage` / compaction lines. |

### Sanitized fixture field set

- Session header: `type: "session"`, `id`, `timestamp` (no `cwd` in retained ledger—workspace label may become a generic tag)
- Assistant messages: `message.role`, `message.provider`, `message.model`, optional `responseModel`
- `usage.{input, output, cacheRead, cacheWrite, reasoning}`; optional `usage.cost.total`
- Underlying provider provenance: **`provider` + `model`** on message or `usage` lines (e.g. `anthropic/claude-sonnet-4`)
- Tool/summary buckets → model key `Tools/summaries` in T3 (retain tokens only)

### Suggested test schema (JSONL)

```json
{"provider":"pi","timestamp":"2026-11-01T12:01:00.000Z","sessionId":"pi-sess-fake-001","underlyingProvider":"anthropic","model":"claude-sonnet-4","rateModel":"claude-sonnet-4","inputTokens":500,"cachedInputTokens":2000,"cacheCreationTokens":0,"outputTokens":120,"reasoningTokens":0}
```

### Confidence

**High** for directory layout and Pi JSONL entry types (OpenUsage + T3). **Medium** for exact optional fields (`responseModel`, `usage` on `toolResult`).

**Links:** [Pi provider](https://openusage.sh/docs/providers/pi/), [T3 usage.md (Pi paths)](https://github.com/pingdotgg/t3code/blob/main/docs/user/usage.md), [ADR-0002 provenance](../adr/0002-track-runtime-sources-with-provider-provenance.md)

---

## 3. xAI Grok (local activity)

### Likely surface (hypothesis)

The product slice targets **local session activity**, not the OpenUsage **xAI API platform** tile (`XAI_API_KEY` → credits/RPM) ([xAI provider](https://openusage.sh/docs/providers/xai/)).

| Source | Path | Notes |
| --- | --- | --- |
| **Grok Build CLI sessions (hypothesis)** | `$GROK_HOME/sessions/<encoded-cwd>/<session-id>/` (default `~/.grok/sessions/`) | [Grok sessions guide](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/17-sessions.md) |
| Token rollup file | `signals.json` per session | CodexBar `GrokLocalSessionScanner`: `totalTokensBeforeCompaction + contextTokensUsed`, `primaryModelId`, `modelsUsed` ([scanner source](https://github.com/steipete/CodexBar/blob/main/Sources/CodexBarCore/Providers/Grok/GrokLocalSessionScanner.swift)) |
| Transcript usage (alternate parser) | `updates.jsonl` ACP `turn_completed` events | T3 [`provider-grok/usage.ts`](https://github.com/pingdotgg/t3code/blob/main/packages/provider-grok/src/server/usage.ts) — `params.update.usage` with camelCase token fields |
| CodexBar (quota) | `grok agent stdio` `_x.ai/billing`, CLI proxy, `~/.grok/auth.json` | Billing/quota path; **out of scope** for sanitized local token fixtures except identity of “local fallback when RPC fails” ([grok.md](https://github.com/steipete/CodexBar/blob/main/docs/grok.md)) |

**Adapter recommendation:** Prefer **`signals.json` aggregation** for low-PII local totals; optionally parse **`updates.jsonl`** for per-turn model splits (never retain conversation lines).

### Sanitized fixture field set

From `signals.json` (hypothesis):

- `primaryModelId`, `modelsUsed[]`
- `totalTokensBeforeCompaction`, `contextTokensUsed` (derive total session tokens)
- Session id + day bucket from file mtime (not path)

From `updates.jsonl` (hypothesis):

- `params.sessionId`, `params.update.sessionUpdate == "turn_completed"`, `params.update.prompt_id`
- `params.update.usage.{inputTokens, outputTokens, cachedReadTokens, cacheCreationTokens, reasoningTokens, costUsdTicks, modelUsage}`

### Suggested test schema (JSONL)

Fixture file models **one sanitized signals snapshot per line** (simpler than shipping fake `updates.jsonl` chat):

```json
{"provider":"grok","sourceKind":"local-signals","sessionId":"grok-sess-fake-001","observedAt":"2026-11-02T09:30:00.000Z","primaryModelId":"grok-4-0606","totalTokensBeforeCompaction":18000,"contextTokensUsed":1200}
```

Optional second line shape for transcript parser tests:

```json
{"provider":"grok","sourceKind":"local-transcript","timestampMs":1730811600000,"sessionId":"grok-sess-fake-001","promptId":"prompt-fake-001","model":"grok-4-0606","inputTokens":1000,"outputTokens":200,"cachedReadTokens":100,"cacheCreationTokens":0,"reasoningTokens":50}
```

### Confidence

**High** for session root layout and `signals.json` fields (CodexBar + xAI Grok Build docs). **Medium** for T3 `updates.jsonl` wire shape (derived from T3 parser, not a published xAI schema doc).

**Links:** [Grok Build sessions](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-pager/docs/user-guide/17-sessions.md), [CodexBar Grok provider](https://github.com/steipete/CodexBar/blob/main/docs/grok.md), [OpenUsage xAI (API — distinct)](https://openusage.sh/docs/providers/xai/)

---

## 4. Z.ai (explicit user credential)

### Likely surface (hypothesis)

| Source | Auth | Endpoints (global `https://api.z.ai`) |
| --- | --- | --- |
| **API platform (hypothesis)** | User-owned `ZAI_API_KEY` (or China `ZHIPUAI_API_KEY` + `open.bigmodel.cn`) | Documented in [OpenUsage Z.AI](https://openusage.sh/docs/providers/zai/): `/api/monitor/usage/quota/limit`, `/api/monitor/usage/model-usage`, `/api/monitor/usage/tool-usage`, `/api/paas/v4/user/credit_grants`, coding `/models` |
| Auto-detection side channel | `~/.chelper/config.yaml` (OpenUsage detection only) | **Do not** store in ledger; Keychain-only in app |

No local JSONL transcript path is documented for Z.ai in OpenUsage/T3 comparable to Claude/Codex; treat as **remote monitor API** with explicit credential.

### Sanitized fixture field set

Retain from API responses (redacted):

- Quota windows: `limits[].{type, unit, number, percentage, nextResetTime, remaining, usage}` (`TOKENS_LIMIT` / `CREDIT_LIMIT`)
- Subscription: `productName`, `status`, `billingCycle` (no account ids)
- Model usage rollups: per-model `totalTokensUsage`, `totalModelCallCount`, input/output/reasoning/cached splits when present
- Tool usage counts (web search / fetch) as **counts only**

### Suggested test schema (JSON)

Single fixture object mimicking a **redacted fetch bundle** (not a raw HTTP trace):

```json
{
  "provider": "zai",
  "region": "global",
  "fetchedAt": "2026-11-03T10:00:00.000Z",
  "quota": { "limits": [] },
  "subscription": { "products": [] },
  "modelUsage": { "models": [] }
}
```

(See `zai-usage.fixture.json` for filled synthetic values.)

### Confidence

**High** for endpoint list and quota envelope shape (OpenUsage docs + `ZAILiveResponseMappingTests`). **Low** for full `model-usage` time-series JSON (OpenUsage notes payload drift; reconcile against live key in S9).

**Links:** [Z.AI provider](https://openusage.sh/docs/providers/zai/), [OpenUsage env vars (`ZAI_API_KEY`)](https://openusage.sh/docs/reference/env-vars/), [Auto-detection (`~/.chelper/config.yaml`)](https://openusage.sh/docs/concepts/auto-detection/)

---

## 5. Antigravity (local)

### Likely surface (hypothesis)

Two public patterns; app may need a **source-kind** switch:

| Pattern | Surface | Tracks |
| --- | --- | --- |
| **OpenUsage CLI integration (hypothesis)** | `agy` status-line JSON on stdin → snapshot at `${XDG_STATE_HOME}/openusage/antigravity-status.json` | Model, context %, session token parts, quota fractions ([Antigravity CLI provider](https://openusage.sh/docs/providers/antigravity/)) |
| **CodexBar / IDE local (hypothesis)** | Antigravity `language_server` or `agy` localhost HTTPS | Quota/session when IDE/CLI running ([antigravity.md](https://github.com/steipete/CodexBar/blob/main/docs/antigravity.md)) |
| **T3 Code (hypothesis)** | Local conversation DB under Antigravity data dir (`ANTIGRAVITY_DATA_DIR`) | Protobuf/SQLite usage rows via [`antigravityUsageReader.ts`](https://github.com/pingdotgg/t3code/blob/main/apps/server/src/provider/Drivers/antigravityUsageReader.ts) |
| **OpenUsage desktop (alternate)** | OAuth quota summary API (`retrieveUserQuotaSummary`) | Not local; useful for reconciliation only ([AntigravityUsageMapper tests](https://github.com/robinebers/openusage/blob/main/Tests/OpenUsageTests/AntigravityProjectQuotaTests.swift)) |

Fixtures use **status-line-shaped JSONL** (one snapshot per line) aligned with OpenUsage’s documented fields, not raw brain/transcript directories.

### Sanitized fixture field set

- `model`, generic `workspaceLabel`
- `contextWindowPct`
- Session token parts: input, output, cache read, total
- Quota buckets: `bucketId`, `remainingFraction`, `resetTime`
- `planTier`, `agentState`, `cliVersion`, opaque `sessionId`

### Suggested test schema (JSONL)

```json
{"provider":"antigravity","sourceKind":"status-line","capturedAt":"2026-11-04T16:00:00.000Z","sessionId":"ag-sess-fake-001","model":"gemini-3.1-pro","workspaceLabel":"fixture-workspace","contextWindowPct":14,"sessionTokens":{"input":12000,"output":3400,"cacheRead":8000,"total":23400},"quotas":[{"bucketId":"gemini-5h","remainingFraction":0.94,"resetTime":"2026-11-05T18:00:00Z"}],"planTier":"g1-pro-tier","agentState":"idle","cliVersion":"2.0.0"}
```

### Confidence

**Medium** for OpenUsage status-line field names (docs list metrics; exact JSON keys not fully specified in public docs). **Medium** for T3 DB/protobuf path (implementation-heavy). **High** that credentials and transcripts must stay out of scope.

**Links:** [Antigravity CLI (OpenUsage)](https://openusage.sh/docs/providers/antigravity/), [CodexBar Antigravity](https://github.com/steipete/CodexBar/blob/main/docs/antigravity.md), [T3 usage (Antigravity dirs)](https://github.com/pingdotgg/t3code/blob/main/docs/user/usage.md)

---

## Reference matrix

| Provider | OpenUsage | CodexBar | T3 Code |
| --- | --- | --- | --- |
| Claude | `claude_code` JSONL | CLI + web strategies | `claudeUsage.ts` |
| Pi | `pi` JSONL | (via shared local agents ecosystem) | `provider-pi/usage.ts` |
| Grok | `xai` API (not local) | `GrokLocalSessionScanner` + CLI billing | `provider-grok/usage.ts` |
| Z.ai | `zai` API | plugin / z.ai | usage docs (API) |
| Antigravity | `antigravity` status-line | local LSP + OAuth fallback | `antigravityUsageReader.ts` |

---

## Gaps / follow-ups

1. **Grok:** Product wording is “local activity”; public OpenUsage tile is API-only—confirm adapter uses **Grok CLI `signals.json` and/or `updates.jsonl`**, not `XAI_API_KEY` management API.
2. **Antigravity:** Exact status-line JSON schema is not published line-by-line; reconcile against a captured **redacted** `antigravity-status.json` or stdin payload when a user-authorized source exists (S9).
3. **Z.ai:** Full `model-usage` body varies; fixture uses minimal rollup; live reconciliation required before Supported.
4. **Claude:** Advisor `usage.iterations` and multi-line content blocks need dedupe tests beyond minimal fixtures.
5. **Pi:** `cwd` in session header is useful for workspace labels in OpenUsage but should not enter this app’s ledger (privacy).
6. **T3 vs OpenUsage repo drift:** OpenUsage’s GitHub tree is Swift-first; some older Go doc paths 404—prefer **openusage.sh** docs and T3/CodexBar source linked above.
