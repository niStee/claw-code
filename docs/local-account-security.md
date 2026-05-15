# Local Account Security Model

This repo uses Claw through local OpenAI-compatible routes. The goal is to spend subscription and free-quota providers first while keeping accounts, credentials, and risky routes separated.

## Operating Rules

- Keep `work-account@example.com` as the only account for Gemini CLI experiments in this repo.
- Keep `personal-account@example.com` out of Gemini CLI, Google Cloud, and Antigravity experiments for this repo. Active Google routes should use repo-local mozmail profiles only.
- Keep Antigravity direct-only and machine-local. Do not place it in any `claw-*` fallback lane.
- Keep DeepSeek as paid overflow only. It must be last in fallback lanes that include it.
- Keep LiteLLM, route tap, Codex proxy, VS Code LM proxy, and Antigravity proxy bound to `127.0.0.1`.
- Keep shared repo config minimal. Put machine-local aliases, keys, profiles, and sessions in ignored local files or DPAPI storage.

## Account Boundaries

| Surface | Intended account/source | Local boundary | Notes |
| --- | --- | --- | --- |
| Gemini CLI | `work-account@example.com` | `scripts/gemini-cli-mozmail.ps1` sets `GEMINI_CLI_HOME=E:\claw-code\profiles\gemini-mozmail` and `GEMINI_FORCE_FILE_STORAGE=true` | Use this wrapper instead of bare `gemini` for repo work. |
| AI Studio API key | AI Studio project/key | DPAPI key `gemini.enc` loaded by proxy scripts | API-key route, separate from Gemini CLI OAuth. |
| Google Cloud / Vertex ADC | Dedicated Cloud project/account for Claw | `scripts/claw-gcloud-mozmail.ps1` pins `CLOUDSDK_CONFIG` to `E:\claw-code\profiles\gcloud-mozmail` | Keep direct-only until billing is enabled. Do not read project/account defaults from global gcloud state. |
| Route tap | Local trace of actual LiteLLM deployments | Local proxy on `127.0.0.1:8099` writing `logs/claw-routes.ndjson` | Use this as Roo Code's base URL when you want selected-model visibility without extra calls. |
| Codex proxy | ChatGPT Plus browser/OAuth state | Local proxy on `127.0.0.1:8089` | Subscription route; do not expose outside localhost. |
| VS Code LM | Copilot/VS Code account | VS Code-owned local proxy on `127.0.0.1:4000` | Use as quota route when VS Code is running. |
| DeepSeek | Pay-as-you-go API key | DPAPI key `deepseek.enc` | Overflow only. |
| Antigravity | `work-account@example.com`, if you accept the risk | Local-only direct alias on `127.0.0.1:4999` | Never default fallback; keep personal out. |

## Non-Google Route Notes

- Route tap forwards Roo/Claw requests to LiteLLM and records response headers such as `x-litellm-model-id`, fallback count, provider base, call id, and the response `model` field when present. It does not log prompts or response text.
- Codex proxy uses ChatGPT browser/OAuth state and is forced through `scripts\codex-proxy-runner.mjs`, which binds to `127.0.0.1`. Do not run the upstream proxy directly from `scripts\codex-proxy` unless you have also checked its `server.host`.
- VS Code LM is owned by the VS Code extension. Treat it as local-only; if it ever listens on anything except loopback, stop it before using Roo Code or Claw. Run `scripts\claw-vscode-lm-localhost.ps1` after installing or updating `ryonakae.vscode-lm-proxy`.
- DeepSeek is a normal pay-as-you-go API key route. Keep the key in DPAPI storage, never in `.env`, and keep it at the end of fallback chains.
- Antigravity is not part of normal routing. Only start it manually, only on this machine, and only with the mozmail account.

## Credential Repair

DPAPI-encrypted files are bound to the current Windows user context. If a stored key was created under another profile, moved between machines, or otherwise becomes unreadable, LiteLLM will start with dummy provider values and that provider will fail over.

Check without printing secrets:

```powershell
scripts\claw-cred.ps1 -Action Test
```

Re-store broken secrets with the secure prompt form, not `-Key`, so the value is not written to shell history:

```powershell
scripts\claw-repair-credentials.ps1
```

Or repair one secret at a time:

```powershell
scripts\claw-cred.ps1 -Action Set -Provider gemini
scripts\claw-cred.ps1 -Action Set -Provider deepseek
scripts\claw-cred.ps1 -Action Set -Provider vertex-project
```

After repairing credentials, restart the stack:

```powershell
scripts\claw-stack.ps1 stop
scripts\claw-stack.ps1 start
scripts\claw-route-probe.ps1 haiku
```

## Recommended Lanes

- `claw-opus`: heavy reasoning and hard implementation. Use Codex GPT-5.5 first, allow one Codex saver fallback, then switch to Copilot `auto`, then DeepSeek.
- `claw-sonnet`: normal coding and review. Use Codex GPT-5.4 first, allow one cheaper Codex fallback, then switch to Copilot `auto`, then callable AI Studio Flash, then DeepSeek.
- `claw-haiku`: quick edits, light tool calls, status checks. Use callable AI Studio Flash-Lite first, then switch to Copilot `auto`, then DeepSeek flash overflow.
- `claw-pro`: high-quality non-lightweight fallback lane. Same provider-bucket shape as `claw-opus`: Codex high-end, one Codex saver fallback, Copilot `auto`, then DeepSeek.
- Direct aliases remain available for provider-specific testing, but Roo Code and normal `claw` usage should use the `claw-*` lanes.
- Short alias `gemini` points to AI Studio Flash for quota-safe use. Use
  `vertex` or `vertex-gemini-*` when you intentionally want the direct
  Google Cloud / Vertex route.

The important rule is provider-bucket awareness. Do not build a long fallback
ladder out of many models from the same subscription. If a provider starts
returning repeated `429`s, sibling models may also be constrained by the same
session, weekly, or monthly bucket. The current config gives Codex one
same-provider fallback because smaller Codex models have higher local-message
headroom, then moves to another provider.

## Provider Limit Buckets

See `docs/model-limit-snapshot.md` for the current source-backed limit snapshot.

| Provider | Current limit shape | Routing consequence |
| --- | --- | --- |
| Codex / ChatGPT Plus | Model-specific local-message ranges exist, but local and cloud tasks share a five-hour window and weekly limits may apply. Local Codex, cloud Codex, and other agentic ChatGPT features can draw from the same included usage pool. | Use GPT-5.5/GPT-5.4 where they fit, but only one smaller Codex fallback before switching providers. |
| VS Code LM / Copilot Student | Copilot has session and rolling seven-day token limits, plus a monthly premium-request allowance. Included models can still be rate-limited during high usage. | Prefer `vscode-auto` in fallback lanes; it is designed to reduce model-specific rate limiting and avoid bad pinned choices like the observed `vscode-gpt-5.2` 429 burst. |
| AI Studio API key | Gemini API limits are per project and vary by model. A lower model may survive a model-specific limit, but project-level quota and missing/broken keys affect all AI Studio routes. | Keep Flash/Lite in `haiku`; do not use AI Studio Pro as an automatic fallback while it is quota-limited. |
| Google Cloud / Vertex | Quotas are project/region/model based and Cloud billing/IAM must be correct. | Keep Vertex routes direct-only until the mozmail project has billing/IAM/quota verified. |
| DeepSeek | Pay-as-you-go route with dynamic server-load concurrency limits. | Keep last. Treat it as paid overflow, not a default lane. |
| Antigravity | Risky machine-local OAuth route. | Direct-only and manual; never in automatic fallback lanes. |

Current endpoint-derived policy:

- AI Studio Pro models may be listed but are excluded from automatic fallbacks while generation returns quota `429`.
- Vertex / Google Cloud models are excluded from automatic fallbacks while project billing is disabled.
- AI Studio Flash/Lite, Codex proxy, VS Code LM, and DeepSeek remain callable according to live endpoint checks.
- Codex proxy `claude-*` names are local shell aliases (`claude-opus-4-7` -> `gpt-5.5`, `claude-sonnet-4-6` -> `gpt-5.4`, `claude-haiku-4-5` -> `gpt-5.3-codex`), not real Anthropic access. Do not put them in automatic fallback lanes.

## Daily Checks

Run this before a longer coding session:

```powershell
scripts\claw-security-status.ps1
scripts\claw-route-status.ps1
scripts\claw-route-last.ps1
scripts\claw-stack.ps1 status
scripts\claw-stack-autostart.ps1 Status
```

Expected safe state:

- Repo-local Gemini profile is either not logged in yet or logged in as `work-account@example.com`.
- Global Gemini/gcloud should not contain active personal Google auth for these routes; repo scripts do not depend on global Google state.
- `providerFallbacks.primary` is absent.
- Antigravity does not appear in any fallback lane.
- DeepSeek appears only at the end of fallback lanes.
- `profiles/`, `logs/`, `downloads/`, `tools/`, `.env*`, `*.enc`, and `.claw/settings.local.json` remain ignored.

For Roo Code selected-model visibility, use:

```text
Base URL: http://127.0.0.1:8099/v1
API key:  sk-claw-unified-proxy-key
```

Roo Code does not run `claw.exe`; it uses Roo's own agent/tool layer and calls
the LiteLLM `claw-*` lanes as OpenAI-compatible model names. To use Claw Code's
own runtime, run `claw` itself from this repo after pointing the shell at the
unified route:

```powershell
scripts\claw-provider.ps1 unified
claw --model sonnet prompt "Implement the next scoped coding task."
```

Then inspect the last actual routes without making extra model calls:

```powershell
scripts\claw-route-last.ps1
```

For a session summary, including idle gaps and rate-limit bursts, run:

```powershell
scripts\claw-roo-usage-report.ps1
```

`GET /v1/models` calls are metadata discovery calls and should not consume model
tokens. Actual model use appears as `POST /v1/chat/completions`. If Roo Code hits
a burst of `429` failures, pause the task and inspect the selected backend before
continuing; repeated agent retries can burn quota on large prompts once a provider
becomes healthy again. In the observed Roo session, idle time only showed model
list calls, while the real failures were repeated `vscode-gpt-5.2` chat
completion attempts.

`scripts\claw-stack.ps1 status` also prints provider credential health. If
Gemini, DeepSeek, or Vertex show `needs repair`, the stack may still list those
models but calls will fail until the DPAPI secrets are re-stored or equivalent
environment variables are set before startup.

The route tap rotates `logs\claw-routes.ndjson` once it reaches 10 MB by
default. Tune with `CLAW_ROUTE_TAP_MAX_LOG_BYTES` and
`CLAW_ROUTE_TAP_MAX_ROTATED`. It also tracks consecutive `429` responses by
requested model. The default mode logs warnings only; set
`CLAW_ROUTE_TAP_CIRCUIT_BREAKER=block` before startup to return local `503`
responses after repeated `429`s instead of resending full prompts upstream.

If VS Code LM is reported as exposed, run:

```powershell
scripts\claw-vscode-lm-localhost.ps1
```

Optional local stack autostart:

```powershell
scripts\claw-stack-autostart.ps1 Install
scripts\claw-stack-autostart.ps1 Status
scripts\claw-stack-autostart.ps1 Remove
```

Autostart starts the local Codex proxy, unified LiteLLM proxy, and route tap. It does not start Antigravity, and it does not own the VS Code LM extension.

## Google Cloud Cleanup Path

For Cloud/Vertex use, avoid sharing the global `%APPDATA%\gcloud` state. The clean path is:

1. Use `scripts\claw-gcloud-mozmail.ps1` so `CLOUDSDK_CONFIG` is pinned to `E:\claw-code\profiles\gcloud-mozmail`.
2. In that isolated profile, run `gcloud init` or `gcloud auth application-default login` with the intended mozmail or project-specific account.
3. Store the project id with `scripts\claw-cred.ps1 -Action Set -Provider vertex-project -Key PROJECT_ID`, or set `VERTEX_PROJECT_ID` for the current shell.
4. Only promote Vertex/Gemini Cloud routes after `scripts\claw-security-status.ps1` shows the isolated config and ADC file.

Useful commands:

```powershell
scripts\claw-gcloud-mozmail.ps1 init
scripts\claw-gcloud-mozmail.ps1 auth application-default login
scripts\claw-gcloud-mozmail.ps1 config set project PROJECT_ID
scripts\claw-gcloud-mozmail.ps1 config configurations list
powershell -NoProfile -File scripts\claw-cred.ps1 -Action Set -Provider vertex-project -Key PROJECT_ID
```

After cleanup, `scripts\claw-security-status.ps1` should report no active global personal Google auth. Prefer archiving old logs/profiles over deleting forensic context.
