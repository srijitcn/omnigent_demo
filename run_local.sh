#!/usr/bin/env bash
#
# run_local.sh — tiny wrapper: derive WORKSPACE_NAME (the Genie MCP URL host)
# from your Databricks profile, then `omnigent run .`. That host is the only
# thing Omnigent needs from the environment — all auth (models + Genie) comes
# from the profile pinned in config.yaml, so there's nothing else to set.
#
#   ./run_local.sh -p "your goal"                    # interactive (pauses at the plan)
#   ./run_local.sh --auto -p "your goal"             # auto-approve, end-to-end
#   DATABRICKS_PROFILE=<name> ./run_local.sh -p ...  # host from a different profile (default: ci-demo)
#
# (Not required — you can instead `export WORKSPACE_NAME=<host>` once and run
#  `omnigent run . -p ...` directly.)
#
set -euo pipefail
cd "$(dirname "$0")"

# Seed the (gitignored) runtime ontology file from the template on first run.
[ -f ontology_context.md ] || cp ontology_context.md.template ontology_context.md 2>/dev/null || true

PROFILE="${DATABRICKS_PROFILE:-DEFAULT}"

# WORKSPACE_NAME = the profile's workspace host (no scheme / trailing slash),
# read straight from ~/.databrickscfg.
ws="$(awk -v p="[$PROFILE]" '
  $0==p{f=1;next} /^\[/{f=0}
  f&&/^host/{sub(/^host[[:space:]]*=[[:space:]]*/,"");print;exit}
' "$HOME/.databrickscfg" 2>/dev/null)"
ws="${ws#http://}"; ws="${ws#https://}"; ws="${ws%/}"
[ -n "$ws" ] || { echo "run_local.sh: no host for profile '$PROFILE' in ~/.databrickscfg" >&2; exit 1; }
export WORKSPACE_NAME="$ws"

# --auto → fold an auto-approve directive into the -p goal; all other args pass through.
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
