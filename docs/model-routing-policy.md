# Model routing policy

This document describes how to combine multiple model providers without turning
provider routing into the agentic orchestration layer.

Claw should see semantic work lanes. A local gateway, if present, should decide
which concrete provider serves that lane at request time. Workflow systems such
as OmX, clawhip, and OmO decide what work should be delegated, when review is
needed, and which lane is appropriate. Provider gateways should remain boring
transport and quota machinery.

## Layer boundary

| Layer | Owns | Should not own |
| --- | --- | --- |
| Claw CLI/runtime | prompts, tools, permissions, sessions, skills, MCP/plugin surfaces, worker state | account-specific quota gymnastics |
| Workflow/orchestration | task decomposition, lane choice, handoffs, review loops, retry policy, event routing | low-level API key selection |
| Provider gateway | concrete model selection inside a lane, fallback on retryable provider failures, quota/cooldown enforcement | deciding whether a task needs architecture review or a lightweight scout |

The important rule is: **choose the lane because of the task, choose the
provider because of availability, cost, and capability.**

## Terms

- **Task class**: the kind of work being requested, such as scouting,
  implementation, review, or provider-specific reasoning.
- **Semantic lane**: the model name Claw or a workflow asks for, such as
  `haiku`, `sonnet`, `opus`, or `pro`.
- **Provider bucket**: a shared limit/cost pool. Multiple concrete models can
  belong to one bucket, so exhausting a premium route can imply that sibling
  routes are constrained too.
- **Route**: one concrete backend model behind a semantic lane.
- **Cooldown**: a temporary provider-bucket hold after rate limits, quota
  failures, or repeated transport failures.
- **Manual route**: an explicit model that must never appear in automatic
  fallbacks because it has account, security, cost, or policy risk.

## Semantic lanes

| Lane | Intended work | Capability floor | Fallback posture |
| --- | --- | --- | --- |
| `haiku` | scouting, summarization, status checks, log reading, low-risk read-only tasks | cheap, fast, enough tool-call reliability for simple read/search loops | degrade freely within low-cost buckets; avoid premium quota |
| `sonnet` | default coding, tests, refactors, debugging, ordinary agentic work | reliable tool calling, sufficient context window for code edits, stable streaming | prefer another capable coding route over a weak cheap route |
| `opus` | architecture, hard bug triage, security review, final review, risky decisions | highest available reasoning quality, strong instruction following, large enough context | fail clearly before falling to a much weaker model |
| `pro` | explicit provider-family reasoning, for example a Google/Gemini-heavy lane | strong reasoning on the targeted provider family | spend this bucket intentionally, not invisibly |

These lanes are semantic. They do not require one specific vendor. If a provider
changes, the lane meaning should stay stable.

## Provider buckets

### Subscription buckets

Examples: ChatGPT/Codex subscription routes, VS Code LM or Copilot routes, other
prepaid model subscriptions.

- Treat limits as shared per subscription bucket unless the provider documents
  and the gateway verifies independent limits.
- If a high-end model in the bucket returns rate-limit or quota errors, assume
  lower-end siblings may also be constrained.
- Cool down the bucket, not just the exact deployment, after repeated 429s.
- Do not let client-side retries resend the same large prompt repeatedly while
  the bucket is already rate-limited.

### Credit buckets

Examples: one-time cloud credits or trial credits.

- Treat credits as real spend even if they are prepaid or promotional.
- Prefer explicit lanes or documented fallback points before consuming credits.
- Surface credit-bucket use in logs/status so it is not invisible.
- Do not use credit buckets for low-value `haiku` work unless the user has made
  that tradeoff explicit.

### Pay-as-you-go buckets

Examples: metered API accounts.

- Use as overflow, not default primary, unless the user explicitly chooses that.
- Put pay-as-you-go routes after prepaid subscription and planned credit routes.
- Keep cost reporting and selected-provider visibility enabled.
- Prefer a clear failure over surprise paid usage when the task is low priority.

### Manual or risky buckets

Examples: private OAuth bridges, account-sensitive local integrations, or routes
that should stay bound to one machine/profile.

- Never include these routes in automatic fallback chains.
- Expose them as explicit direct aliases only.
- Keep account/profile isolation documented outside shared defaults.
- Use for deliberate manual review or experiments, not unattended routing.

### Local buckets

Examples: Ollama, llama.cpp, vLLM, or a local OpenAI-compatible server.

- Prefer for cheap scouting and offline workflows when the model supports the
  required tool-call shape.
- Do not route coding lanes to local models unless their context window and
  tool-call behavior are verified for the workload.
- Treat a passing plain prompt as necessary but not sufficient; smoke-test tool
  calls before using local models in agentic loops.

## Fallback rules

1. Fallback only on retryable provider failures such as rate limits, transient
   5xx errors, or gateway transport failures.
2. Do not fallback across capability cliffs. A coding lane should not silently
   fall to a model that cannot use the required tools or context window.
3. Do not fallback from a high-confidence review lane to a weak model that may
   produce false confidence. For `opus`, a clear failure is often better.
4. Cool down provider buckets after repeated failures. Avoid hammering a single
   route through client retries.
5. Keep manual routes out of automatic chains.
6. Keep paid overflow last unless the user intentionally reorders the policy.
7. Preserve lane intent. A provider gateway may change the backend model, but it
   should not reinterpret `haiku` work as `opus` work or the reverse.

## Context and tool-call floors

Every lane should define minimum viable capability before it is placed behind
agentic workflows:

| Lane | Minimum context guidance | Tool-call guidance |
| --- | --- | --- |
| `haiku` | enough for target files, logs, and summaries | read/search tools should be reliable |
| `sonnet` | enough for multi-file coding sessions and test output | edit, shell, read/search, and structured outputs should be reliable |
| `opus` | enough for full design/review context | tool use may be lighter, but reasoning and review quality must stay high |
| `pro` | provider-specific; document expected context per route | verify the targeted provider's tool-call compatibility before default use |

If a fallback route has a much smaller context window than the primary route, it
should either be excluded from that lane or guarded by a gateway-side context
limit. Do not discover context mismatch only after a long agent session has
already built up.

## Observability contract

A multi-provider setup should expose the actual backend without spending extra
tokens. At minimum, logs or status output should include:

- requested semantic lane
- selected provider bucket
- selected concrete model/deployment
- whether a fallback was used
- status code or retryable error class
- call id or trace id
- duration
- cost class, such as subscription, credit, pay-as-you-go, local, or manual

This visibility should come from gateway response headers, local trace logs, or
provider metadata. It should not ask the model to report its own identity.

## Claw configuration guidance

Use Claw settings to expose stable semantic lanes:

```json
{
  "model": "sonnet",
  "aliases": {
    "haiku": "openai/claw-haiku",
    "sonnet": "openai/claw-sonnet",
    "opus": "openai/claw-opus",
    "pro": "openai/claw-pro"
  }
}
```

Use machine-local settings, such as `.claw/settings.local.json`, for local
gateway aliases. Keep shared repository defaults provider-neutral unless the
project intentionally requires one provider.

Claw's `providerFallbacks` setting is useful for simple direct-provider chains.
For quota-aware multi-provider setups, prefer implementing bucket cooldowns and
route selection in the gateway or workflow layer. Avoid setting
`providerFallbacks.primary` unless the intent is to override the selected model
for every task in that config scope.

## Agent and workflow guidance

Agent definitions should describe work roles, not billing mechanics. A useful
agent definition can name its intended model lane, but the agent's job remains
semantic:

- explorer or scout -> `haiku`
- implementation worker -> `sonnet`
- verifier or reviewer -> `opus` when the risk justifies it, otherwise `sonnet`
- provider-specific experiment -> `pro`

Workflow systems should decide when to escalate from `haiku` to `sonnet` or from
`sonnet` to `opus`. Provider gateways should decide only how to serve the lane
that was requested.

## Non-goals

- Do not encode private account names, API keys, OAuth identities, or local
  machine paths in shared policy docs.
- Do not make Rust provider code carry local quota policy unless the behavior is
  general enough to benefit upstream users.
- Do not depend on terminal prose when structured status, route logs, or event
  metadata are available.
- Do not treat external editor clients as the source of truth for selected
  backend models unless they surface provider metadata reliably.
