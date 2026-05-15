# Model Limit Snapshot

Last checked: 2026-05-15.

This is the routing-relevant view of the provider limits. Exact availability can
still change at the account, project, plan, and model level, so the local route
tap remains the source of truth for what was actually used.

## Codex / ChatGPT Plus

OpenAI publishes model-specific Codex local-message ranges for Plus:

| Model | Plus local messages / 5h | Current routing role |
| --- | ---: | --- |
| GPT-5.5 | 15-80 | `claw-opus` and `claw-pro` primary |
| GPT-5.4 | 20-100 | `claw-sonnet` primary |
| GPT-5.4-mini | 60-350 | one saver fallback for `claw-sonnet` |
| GPT-5.3-Codex | 30-150 | one saver fallback for `claw-opus` / `claw-pro` |

Local messages and cloud tasks share a five-hour window, and additional weekly
limits may apply. That means a smaller Codex fallback is worth trying, but long
same-provider fallback chains are not worth hammering after repeated limit
errors.

Source: https://developers.openai.com/codex/pricing

## GitHub Copilot / VS Code LM

Copilot Student currently lists 300 premium requests per month. Copilot also has
session and rolling seven-day token limits. Included models for paid plans and
Copilot Student are GPT-5 mini, GPT-4.1, and GPT-4o; they do not consume premium
requests, though they can still be rate-limited.

Relevant paid-plan multipliers:

| Model | Premium request multiplier |
| --- | ---: |
| GPT-5.5 | 7.5 |
| GPT-5.4 | 1 |
| GPT-5.4 mini | 0.33 |
| GPT-5.3-Codex | 1 |
| GPT-5.2 / GPT-5.2-Codex | 1 |
| Gemini 3.1 Pro | 1 |
| Gemini 3 Flash | 0.33 |
| Claude Haiku 4.5 | 0.33 |
| Claude Opus 4.7 | 15 |

Use `vscode-auto` in normal fallbacks so Copilot can avoid unhealthy or limited
pinned models. Keep direct VS Code aliases for testing.

Sources:

- https://docs.github.com/en/copilot/get-started/plans
- https://docs.github.com/en/copilot/concepts/usage-limits
- https://docs.github.com/en/copilot/concepts/billing/copilot-requests
- https://docs.github.com/en/copilot/concepts/auto-model-selection

## Gemini API / AI Studio

Gemini API rate limits are measured as RPM, TPM, and RPD. They are applied per
project, not per API key, and limits vary by model. Active limits should be read
from AI Studio because they change with project tier and account state.

Routing consequence: use AI Studio Flash-Lite/Flash for `haiku`, but do not rely
on a ladder of several AI Studio models after project/provider quota errors.

Source: https://ai.google.dev/gemini-api/docs/rate-limits

## Google Cloud / Vertex

Vertex/Gemini quotas are tied to Cloud project, region, model, billing, and IAM.
The local config keeps these routes direct-only until the mozmail project has
billing and access verified.

Source: https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/quotas

## Anthropic / Claude

There is no normal direct Anthropic subscription route in this setup. The real
Claude-looking routes available here are either Copilot-hosted models, covered by
Copilot limits, or Antigravity, which stays direct-only. For Anthropic API
accounts, official rate limits are by organization and model class; Opus 4.x and
Sonnet 4.x each have combined-family limits.

Source: https://platform.claude.com/docs/en/api/rate-limits

## DeepSeek

DeepSeek states that API concurrency is dynamically limited based on server load,
and HTTP 429 is returned when the concurrency limit is reached. It is paid
overflow in this setup.

Source: https://api-docs.deepseek.com/quick_start/rate_limit/
