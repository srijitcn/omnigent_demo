#!/usr/bin/env bash
#
# verify_sandbox.sh — verify a sandbox (Databricks lakebox or any Linux host) is
# ready to RUN ontogent. It installs NOTHING — it only checks that the required
# tools, Omnigent harness SDKs, environment variables, and agent files are in
# place, then prints a PASS/FAIL summary and exits non-zero if anything required
# is missing.
#
# On a Databricks-managed sandbox, Omnigent + its deps are already baked into the
# image and credentials are ambient — this script confirms that reality and tells
# you exactly what (if anything) still needs setting. The Genie MCP host is written
# into config.yaml by ./run_local.sh (the runner scrubs env vars, so it can't be
# one); this script checks that a host is resolvable. Run it from the app directory:
#
#   ./verify_sandbox.sh
#
set -uo pipefail   # (no -e: we want to run every check and summarize, not abort)
cd "$(dirname "$0")"

pass=0; warnc=0; failc=0
ok()   { printf "  \033[32mPASS\033[0m %s\n" "$*"; pass=$((pass+1)); }
warn() { printf "  \033[33mWARN\033[0m %s\n" "$*"; warnc=$((warnc+1)); }
fail() { printf "  \033[31mFAIL\033[0m %s\n" "$*"; failc=$((failc+1)); }
section() { printf "\n\033[1;34m== %s\033[0m\n" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

printf "\033[1montogent sandbox readiness check\033[0m  (%s, %s)\n" "$(uname -s)" "$(uname -m)"

# ---------------------------------------------------------------- required CLIs
section "Required tools"
if have omnigent; then ok "omnigent  ($(omnigent --version 2>&1 | head -1))"
else fail "omnigent not on PATH (on a Databricks sandbox it's baked into the image — this box isn't one)"; fi
if have codex; then ok "codex CLI  ($(codex --version 2>&1 | head -1))   # backs the gpt reviewer (codex harness)"
else fail "codex CLI missing — the gpt reviewer runs on the codex harness (install: npm i -g @openai/codex)"; fi
have git     && ok "git  ($(git --version 2>&1))   # the claude coder commits / opens PRs" || fail "git missing (the coder needs it)"
have python3 && ok "python3  ($(python3 --version 2>&1))" || fail "python3 missing"

# ------------------------------------------------------- Omnigent harness SDKs
section "Omnigent harness SDKs (Python)"
OMNI_PY=""
if have omnigent; then
  sb="$(head -1 "$(command -v omnigent)" 2>/dev/null || true)"
  case "$sb" in \#!*) c="${sb#\#!}"; c="${c%% *}"; [ -x "$c" ] && OMNI_PY="$c";; esac
fi
[ -z "$OMNI_PY" ] && OMNI_PY="$(command -v python3 || true)"
if [ -n "$OMNI_PY" ]; then
  printf "  (using interpreter: %s)\n" "$OMNI_PY"
  # module -> which harness/extra it backs
  check_mod() {  # $1=module  $2=label
    if "$OMNI_PY" -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('$1') else 1)" 2>/dev/null; then
      ok "$2  (import $1)"
    else
      fail "$2 MISSING — import '$1' failed. Reinstall omnigent with the extra."
    fi
  }
  check_mod claude_agent_sdk "claude-sdk  (orchestrator brain + claude sub-agent)"
  check_mod agents           "openai-agents  (gemini sub-agent)"
  check_mod databricks.sdk   "databricks  (Databricks auth / gateway routing)"
else
  fail "no python interpreter found to check harness SDKs"
fi

# --------------------------------------------- Genie MCP host & auth profile
section "Genie MCP host & Databricks profile"
# The profile the agent configs authenticate with (models AND the Genie MCP).
CFG_PROFILE="$(awk '/^[[:space:]]*profile:/ {v=$2; sub(/#.*/,"",v); print v; exit}' config.yaml 2>/dev/null)"
CFG_PROFILE="${CFG_PROFILE:-DEFAULT}"

# The Genie MCP host is a LITERAL in config.yaml (env vars are scrubbed from the
# runner). ./run_local.sh writes it in from the profile before running; here we
# check (a) what's currently in config.yaml, and (b) that a host is resolvable.
GENIE_HOST="$(awk -F'://' '/^[[:space:]]*url:.*\/api\/2\.0\/mcp\/genie/ {split($2,a,"/"); print a[1]; exit}' config.yaml 2>/dev/null)"
RESOLVED_HOST="$(awk -v p="[$CFG_PROFILE]" '
  $0==p{f=1;next} /^\[/{f=0}
  f && /^host/ {sub(/^host[[:space:]]*=[[:space:]]*/,""); print; exit}
' "$HOME/.databrickscfg" 2>/dev/null)"
RESOLVED_HOST="${RESOLVED_HOST:-${DATABRICKS_HOST:-}}"
RESOLVED_HOST="${RESOLVED_HOST#http*://}"; RESOLVED_HOST="${RESOLVED_HOST%/}"

if [ -n "$GENIE_HOST" ] && [ "$GENIE_HOST" != "<workspace-host>" ]; then
  ok "genie_one URL host is set in config.yaml ($GENIE_HOST)"
elif [ -n "$RESOLVED_HOST" ]; then
  warn "genie_one URL is still the <workspace-host> placeholder — ./run_local.sh will write '$RESOLVED_HOST' (profile '$CFG_PROFILE') in before running"
else
  fail "genie_one URL is the <workspace-host> placeholder AND no host resolves for profile '$CFG_PROFILE' — run: databricks auth login -p $CFG_PROFILE (or set \$DATABRICKS_HOST)"
fi

# Auth is by PROFILE now — models and the Genie MCP each mint their own token from
# it at runtime, so DATABRICKS_TOKEN is no longer used.
if [ -z "$(printenv DATABRICKS_TOKEN 2>/dev/null || true)" ]; then
  ok "DATABRICKS_TOKEN not set — expected: auth is via the '$CFG_PROFILE' profile, not a token env var"
else
  warn "DATABRICKS_TOKEN is set — harmless but unused; config authenticates via the '$CFG_PROFILE' profile"
fi

# The profile the config uses must actually authenticate (this is the real auth check).
if command -v databricks >/dev/null 2>&1; then
  if databricks current-user me -p "$CFG_PROFILE" >/dev/null 2>&1; then
    ok "profile '$CFG_PROFILE' authenticates — models + Genie will use it"
  else
    fail "profile '$CFG_PROFILE' did NOT authenticate — run: databricks auth login -p $CFG_PROFILE  (or point config.yaml + agents/*/config.yaml at a valid profile)"
  fi
else
  warn "databricks CLI not on PATH — cannot verify the '$CFG_PROFILE' profile authenticates"
fi

# ----------------------------------------------------- recommended extras
section "Recommended extras"
have tmux && ok "tmux present (terminal harnesses)" || warn "tmux not found (recommended for terminal-based harnesses)"
have jq   && ok "jq present" || warn "jq not found (recommended)"

# --------------------------------------------------------------- agent files
section "ontogent agent files"
for f in config.yaml agents/claude/config.yaml agents/gpt/config.yaml agents/gemini/config.yaml skills/debate/SKILL.md; do
  [ -f "$f" ] && ok "found $f" || fail "missing $f (run this from the ontogent app directory)"
done

# ---------------------------------------------------------------- summary
section "Summary"
printf "  %d passed, %d warnings, %d failed\n" "$pass" "$warnc" "$failc"
if [ "$failc" -eq 0 ]; then
  printf "  \033[32mREADY\033[0m — this sandbox can run ontogent.\n"
  [ "$warnc" -gt 0 ] && printf "  (address the warnings above for a clean run.)\n"
  exit 0
else
  printf "  \033[31mNOT READY\033[0m — fix the %d FAIL item(s) above, then re-run.\n" "$failc"
  exit 1
fi
