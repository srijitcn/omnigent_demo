#!/usr/bin/env bash
#
# install_local.sh — install everything needed to run "ontogent" locally (macOS).
#
# Idempotent: checks what's already present and installs only what's missing.
# After it finishes, run:  omnigent run . -p "I want to build ..."
#
# What it installs:
#   • system tools via Homebrew: uv, tmux, jq, databricks CLI, node (>=22), codex CLI
#   • Omnigent, via the official installer (https://omnigent.ai/install.sh) if it is
#     not already present. This app uses the claude-sdk (brain + claude), openai-agents
#     (gemini), and codex (gpt reviewer) harnesses — enable any missing one with
#     `omnigent setup`. The codex harness is the Codex CLI binary installed above.
#
set -euo pipefail

# --- config ---------------------------------------------------------------
CONFIG_PROFILE="DEFAULT"   # the Databricks profile referenced in the agent configs

# --- pretty output --------------------------------------------------------
step() { printf "\n\033[1;34m==>\033[0m %s\n" "$*"; }
ok()   { printf "  \033[32mOK\033[0m   %s\n" "$*"; }
warn() { printf "  \033[33mWARN\033[0m %s\n" "$*"; }
die()  { printf "  \033[31mERR\033[0m  %s\n" "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# --- 0. platform ----------------------------------------------------------
[ "$(uname)" = "Darwin" ] || die "This script targets macOS. On Linux, install the same tools with your package manager."
have brew || die "Homebrew is required. Install it from https://brew.sh then re-run."

# --- 1. system tools (Homebrew) -------------------------------------------
step "System tools (Homebrew)"

ensure_brew() {  # $1 = command to check, $2 = brew formula
  if have "$1"; then ok "$1 present"; else warn "$1 missing — installing ($2)"; brew install "$2"; fi
}
ensure_brew uv uv
ensure_brew tmux tmux
ensure_brew jq jq

# Databricks CLI (tap-based formula)
if have databricks; then ok "databricks CLI present ($(databricks --version 2>&1 | head -1))"
else warn "databricks CLI missing — installing"; brew tap databricks/tap >/dev/null 2>&1 || true; brew install databricks; fi

# Node >= 22 (Omnigent's web UI)
if have node; then
  node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  if [ "${node_major:-0}" -ge 22 ]; then ok "node $(node --version) (>= 22)"
  else warn "node $(node --version) is < 22 — installing node@22 (may be keg-only; link if needed)"; brew install node@22; fi
else warn "node missing — installing"; brew install node; fi

# Codex CLI — drives the `codex` harness (the GPT reviewer), routed through Databricks.
if have codex; then ok "codex CLI present ($(codex --version 2>&1 | head -1))"
else
  warn "codex CLI missing — installing"
  brew install codex 2>/dev/null || npm install -g @openai/codex || die "Could not install the Codex CLI (try: npm install -g @openai/codex)"
fi

# --- 2. Omnigent ----------------------------------------------------------
step "Omnigent"
if have omnigent; then
  ok "omnigent present ($(omnigent --version 2>&1 | head -1))"
else
  warn "omnigent missing — installing via the official installer"
  curl -fsSL https://omnigent.ai/install.sh | sh
fi
# This app uses the claude-sdk, openai-agents, and codex harnesses. If a run
# reports a missing one, enable it once with:  omnigent setup

# --- 3. verify ------------------------------------------------------------
step "Verify tools"
for t in omnigent omni uv node tmux jq databricks codex; do
  if have "$t"; then ok "$t"; else warn "$t still missing"; fi
done

# --- 4. Databricks auth sanity (models + Genie all use one profile) -------
step "Databricks auth check (profile referenced in configs: '$CONFIG_PROFILE')"
if databricks auth profiles > "/tmp/_dbx_profiles.$$" 2>/dev/null; then
  awk 'NR>1 && $1!="" {printf "     %-22s %-46s valid=%s\n", $1, $2, $NF}' "/tmp/_dbx_profiles.$$"
  if awk -v p="$CONFIG_PROFILE" 'NR>1 && $1==p && $NF=="YES"{f=1} END{exit f?0:1}' "/tmp/_dbx_profiles.$$"; then
    ok "profile '$CONFIG_PROFILE' is valid"
  else
    warn "profile '$CONFIG_PROFILE' is NOT currently valid/found."
    warn "  Fix:  databricks auth login -p $CONFIG_PROFILE"
    warn "  ...or edit executor.auth.profile in config.yaml + agents/*/config.yaml to a valid profile."
  fi
  rm -f "/tmp/_dbx_profiles.$$"
else
  warn "could not list databricks profiles (is the databricks CLI configured?)"
fi

# --- 5. next steps --------------------------------------------------------
step "Done. Next steps to run ontogent locally"
cat <<EOF
  1) Authenticate your Databricks profile — models AND the Genie MCP both use it,
     so there is NO token to export:
       databricks auth login -p $CONFIG_PROFILE

  2) Run it — run_local.sh sets WORKSPACE_NAME (the Genie host) from the profile:
       ./run_local.sh -p "I want to build a churn-risk dashboard"          # interactive
       ./run_local.sh --auto -p "I want to build a churn-risk dashboard"   # end-to-end

  3) (optional) Confirm the served model names exist; adjust config.yaml + agents/*/config.yaml:
       databricks serving-endpoints list | grep -Ei 'claude|gpt-5|gemini'

  (If omnigent reports no default provider, run once:  omnigent setup)
EOF
