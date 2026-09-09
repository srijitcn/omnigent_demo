#!/usr/bin/env bash
#
# run_local.sh — prepare and run ontogent (works on macOS and on a Linux sandbox).
#
# Omnigent spawns its runner with a scrubbed environment, so neither the Genie MCP
# host nor the auth profile in config.yaml can be an env var — both must be literals.
# So before running, this script writes two things into the config files from your
# chosen Databricks profile:
#   • the profile's workspace HOST into config.yaml's `genie_one` URL, and
#   • the PROFILE name into every `auth.profile` (config.yaml + agents/*/config.yaml).
# The repo ships the portable defaults (a `<workspace-host>` placeholder + the DEFAULT
# profile); this localizes them for the run. All auth — models AND Genie — is by
# profile, so there is no token to set.
#
#   ./run_local.sh -p "your goal"                    # interactive (uses config.yaml's profile)
#   ./run_local.sh --auto -p "your goal"             # auto-approve, end-to-end
#   DATABRICKS_PROFILE=<name> ./run_local.sh -p ...  # run under a different profile everywhere
#
set -euo pipefail
cd "$(dirname "$0")"

# Profile: explicit override, else the auth.profile literal already in config.yaml.
cfg_profile="$(awk '/^[[:space:]]*profile:/ {v=$2; sub(/#.*/,"",v); print v; exit}' config.yaml 2>/dev/null || true)"
PROFILE="${DATABRICKS_PROFILE:-${cfg_profile:-DEFAULT}}"

# Derive the workspace host (no scheme / trailing slash): the profile's host in
# ~/.databrickscfg, else $DATABRICKS_HOST (some sandboxes provide it that way).
host="$(awk -v p="[$PROFILE]" '
  $0==p{f=1;next} /^\[/{f=0}
  f && /^host/ {sub(/^host[[:space:]]*=[[:space:]]*/,""); print; exit}
' "$HOME/.databrickscfg" 2>/dev/null || true)"
host="${host:-${DATABRICKS_HOST:-}}"
host="${host#http://}"; host="${host#https://}"; host="${host%/}"
[ -n "$host" ] || { echo "run_local.sh: no host for profile '$PROFILE' in ~/.databrickscfg and \$DATABRICKS_HOST is unset (try: databricks auth login -p $PROFILE)" >&2; exit 1; }

# Localize the config for this run (portable in-place edits via tmpfile+mv):
#   1. the genie_one URL host  — replaces <workspace-host> or any prior host.
#   2. every `auth.profile:`   — in config.yaml and each agents/*/config.yaml,
#      preserving indentation and any trailing comment.
# NOTE: this rewrites tracked files. The concrete host is your workspace's — keep
# it out of the PUBLIC repo: only ever commit the `<workspace-host>` placeholder.
# To restore the committed placeholder before committing:  git checkout -- config.yaml
localize() {  # $1 = file
  local f="$1" tmp; tmp="$(mktemp)"
  sed -E \
    -e "s#(url:[[:space:]]*\"?https?://)[^/\"]*(/api/2\.0/mcp/genie)#\1${host}\2#" \
    -e "s#^([[:space:]]*profile:[[:space:]]*)[^[:space:]#]+#\1${PROFILE}#" \
    "$f" > "$tmp" && mv "$tmp" "$f"
}
localize config.yaml
for a in agents/*/config.yaml; do [ -f "$a" ] && localize "$a"; done
echo "run_local.sh: localized profile='${PROFILE}', genie_one host='${host}' (config.yaml + agents/*/config.yaml)"

# --auto folds an auto-approve directive into the -p goal; other args pass through.
auto=0; prompt=""; have_p=0; pass=()
while [ $# -gt 0 ]; do
  case "$1" in
    --auto)          auto=1; shift ;;
    -p|--prompt)     prompt="${2:-}"; have_p=1; shift 2 ;;
    -p=*|--prompt=*) prompt="${1#*=}"; have_p=1; shift ;;
    *)               pass+=("$1"); shift ;;
  esac
done
if [ "$auto" = 1 ] && [ "$have_p" = 1 ]; then
  prompt="AUTO-APPROVE MODE — treat the plan as pre-approved: don't stop for my approval; continue through implementation and the review-and-fix loop. Keep the normal async pattern (dispatch, read the inbox once, END YOUR TURN so workers re-wake you); do NOT busy-poll. GOAL: ${prompt}"
fi

run=(run .)
[ "$have_p" = 1 ] && run+=(-p "$prompt")
run+=(${pass[@]+"${pass[@]}"})
exec omnigent "${run[@]}"
