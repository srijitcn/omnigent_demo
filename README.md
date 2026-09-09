# ontogent

An **ontology-grounded, multi-model project builder** built as an
[Omnigent](https://omnigent.ai) agent app. Give it a plain-language goal; it
grounds that goal in your data's own vocabulary via a Databricks **Genie** MCP
server, drafts a plan with Claude, has **three model families debate it**, gets
**your approval**, builds the code, and runs a **cross-model review-and-fix
loop** until an independent reviewer signs off.

## The showcase: many models, one credential

Every model runs through a **single Databricks profile** — no OpenAI or Google
API keys anywhere:

| Voice | Family | Model (Databricks-served) | Harness | Role |
|-------|--------|---------------------------|---------|------|
| 🟠 `claude` | Anthropic | `databricks-claude-opus-4-7`   | `claude-sdk`    | plan · implement · fix · debate |
| 🔵 `gpt`    | OpenAI    | `databricks-gpt-5-3-codex`     | `codex`         | review · debate |
| 🟢 `gemini` | Google    | `databricks-gemini-2-5-pro`    | `openai-agents` | debate · optional co-review |

Both the `codex` harness (GPT) and the `openai-agents` harness (Gemini) route a
`databricks-*` model plus an `executor.auth` Databricks profile through the
Databricks gateway — the codex executor generates an "Omnigent Databricks"
provider entry, and openai-agents keys off `allow_ambient_databricks` — so the
GPT and Gemini voices authenticate with the same Databricks credential as Claude,
no vendor keys of their own. (The bundled `sentinel` example uses this same
`harness: codex` + `read_only_os` reviewer pattern.) The native
`antigravity`/`cursor` harnesses are intentionally **not** used — each would need
its own vendor key and break the one-credential story.

## The pipeline

```
goal
  └─▶ 2. Genie grounding      → append keywords + ontology to ontology_context.md
  └─▶ 3. plan (claude)        → implementation plan grounded in the ontology
  └─▶ 4. debate (skills/debate) → claude 🟠 vs gpt 🔵 vs gemini 🟢 → refined plan
  └─▶ 5. present plan to you
  └─▶ 6. YOU approve          ← prompt-driven gate (or `--auto` to skip)
  └─▶ 7. implement (claude)   → writes the code
  └─▶ 8. review loop          → gpt reviews → claude fixes → repeat until PASS
```

## Layout

```
config.yaml                 orchestrator ("ontogent") — brain, tools, guardrails
agents/claude/config.yaml   🟠 Anthropic Claude via Databricks (writes code)
agents/gpt/config.yaml       🔵 OpenAI GPT-5 Codex via Databricks (read-only reviewer)
agents/gemini/config.yaml    🟢 Google Gemini via Databricks (read-only debater)
skills/debate/SKILL.md      3-way debate on the plan, auto-discovered
ontology_context.md.template  seed for the ontology grounding file
```

`ontology_context.md` itself is **gitignored** runtime state — ontogent rewrites it
every run. It's seeded from `ontology_context.md.template` on first run (`run_local.sh`
copies it, and the orchestrator self-seeds if it's missing), so runs never dirty a
tracked file.

## Prerequisites

1. **Install everything** (macOS): run the bundled script. It installs `uv`,
   `tmux`, `jq`, the Databricks CLI, Node ≥22, the Codex CLI, and Omnigent:
   ```bash
   ./install_local.sh
   ```
   (Manual path: install Omnigent with the official installer —
   `curl -fsSL https://omnigent.ai/install.sh | sh` — then run `omnigent setup` to
   enable the `claude-sdk` / `openai-agents` harnesses. The `codex` harness is the
   Codex CLI binary, not a python extra.)
2. **A valid Databricks CLI profile** in `~/.databrickscfg`. This app uses
   `DEFAULT` everywhere — authenticate it (`databricks auth login -p DEFAULT`), or
   change the `profile:` in `config.yaml` and the three `agents/*/config.yaml` to a
   valid one. (`install_local.sh` reports which of your profiles are currently valid.)
3. **Confirm the served model names** exist in your workspace and adjust the
   `model:` fields if needed:
   ```bash
   databricks serving-endpoints list | grep -Ei 'claude|gpt-5|gemini'
   ```
4. **A Genie space.** Auth is by **profile** — the Genie MCP (like the models)
   mints its own bearer token from the `DEFAULT` profile at runtime, so there is
   **no token to set**. The only env var is `WORKSPACE_NAME` (the workspace host
   for the MCP URL), and `run_local.sh` / `source ./sandbox_env.sh` derive it from
   the profile:
   ```bash
   export WORKSPACE_NAME=<your-workspace-host>   # e.g. dbc-xxxx.cloud.databricks.com (no scheme)
   ```
   The MCP URL in `config.yaml` resolves to `https://${WORKSPACE_NAME}/api/2.0/mcp/genie`,
   and it authenticates via `auth: {type: databricks, profile: DEFAULT}`.

## Run

Easiest — `run_local.sh` derives `WORKSPACE_NAME` from your Databricks profile and
runs it. All auth — the models and the Genie MCP — comes from the profile, so
there's no token to set:

```bash
# interactive — pauses at the plan for your approval, then builds:
./run_local.sh -p "I want to build a churn-risk dashboard for subscription accounts"

# auto-approve — runs end-to-end (plan → debate → implement → review), no pause:
./run_local.sh --auto -p "I want to build a churn-risk dashboard for subscription accounts"

# use a different profile:
DATABRICKS_PROFILE=workshop ./run_local.sh -p "..."
```

The profile must be valid (`databricks auth profiles`); if not: `databricks auth login -p <profile>`.

Manual equivalent (the profile supplies all auth; you set only the host):
```bash
export WORKSPACE_NAME=<your-workspace-host>          # no scheme, e.g. dbc-xxxx.cloud.databricks.com
export DATABRICKS_CONFIG_PROFILE=DEFAULT             # models + Genie authenticate via this profile
omnigent run . -p "I want to build ..."
```

**On a Databricks sandbox** (no `~/.databrickscfg` editing needed — the profile is baked):
```bash
source ./sandbox_env.sh     # sets WORKSPACE_NAME from the DEFAULT profile
./verify_sandbox.sh         # confirms tools, SDKs, profile auth, and files
omnigent run . -p "..."
```

The run narrates each step — 🎯 goal, 🧬 the ontology it acquired (keywords +
entities, and whether Genie was used or skipped), 📋 the plan, 🗣️ each debate
voice, 🛠️ files created, 🔍 review verdicts. In **interactive** mode it pauses
after the plan — type `approved` to build. With **`--auto`** it prints
"✅ Auto-approve" and runs straight through. (`omnigent start` runs it as a server
at `:6767` for the web UI / phone, with shareable live sessions.)

## Notes & knobs

- **Approval** is prompt-driven: by default ontogent presents the plan and waits
  for you to approve before implementing. `./run_local.sh --auto` injects an
  auto-approve directive so it proceeds end-to-end without pausing. (There's no
  hard ASK policy — that's what lets the `--auto` toggle bypass the wait cleanly.)
- **Visibility**: the orchestrator narrates each step with markers (🎯 🧬 📋 🗣️
  🛠️ 🔍), including echoing the acquired ontology, so a run is legible as it goes.
- **Loop bounds**: `max_tool_calls_per_session` (ceiling) + a ~5-cycle guidance in
  the prompt keep the review/fix loop finite. (An earlier `detect_loop` policy was
  removed — it misfired on the orchestrator's normal once-per-turn inbox reads.)
- **Auth**: one Databricks **profile** (`DEFAULT`) drives everything — models via
  `executor.auth`, the Genie MCP via `auth: {type: databricks, profile}`. No token
  env var. Change the profile in `config.yaml` + `agents/*/config.yaml` to switch.
- **Sandbox**: `source ./sandbox_env.sh` (sets `WORKSPACE_NAME` from the profile),
  then `./verify_sandbox.sh` to confirm readiness.
- **Ontology grows**: `ontology_context.md` accumulates across runs — later goals
  reuse earlier grounding.
- The default `model:` ids follow the Omnigent docs' examples; swap them for the
  exact endpoint names your workspace serves.
