#!/usr/bin/env bash
# sandbox_env.sh — SOURCE this in a Databricks sandbox to set the one env var the
# ontogent Genie MCP still needs: WORKSPACE_NAME (the workspace host for the MCP
# URL). Auth is handled by the Databricks PROFILE — the models AND the Genie MCP
# each mint their own bearer token from ~/.databrickscfg at runtime, so there is
# NO token to export.
#
#   source ./sandbox_env.sh                       # profile: DATABRICKS_CONFIG_PROFILE or DEFAULT
#   DATABRICKS_CONFIG_PROFILE=myprofile source ./sandbox_env.sh
#
# Sets: WORKSPACE_NAME (host, no scheme) and DATABRICKS_CONFIG_PROFILE (so the
# CLI/SDK default profile matches). Safe to re-source. Never touches any token.

# Must be sourced (if executed, exports can't reach your shell).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  echo "sandbox_env.sh must be SOURCED so the export reaches your shell:" >&2
  echo "    source ./sandbox_env.sh" >&2
  exit 2
fi

_prof="${DATABRICKS_CONFIG_PROFILE:-DEFAULT}"
_cfg="${DATABRICKS_CONFIG_FILE:-$HOME/.databrickscfg}"

# Workspace host:  $DATABRICKS_HOST  →  the profile's host in ~/.databrickscfg
_host="${DATABRICKS_HOST:-}"
if [ -z "$_host" ] && [ -f "$_cfg" ]; then
  _host="$(awk -v p="[$_prof]" '$0==p{f=1;next} /^\[/{f=0} f&&/^host[ \t]*=/{sub(/^host[ \t]*=[ \t]*/,"");print;exit}' "$_cfg")"
fi
_host="${_host#http://}"; _host="${_host#https://}"; _host="${_host%/}"

export DATABRICKS_CONFIG_PROFILE="$_prof"
[ -n "$_host" ] && export WORKSPACE_NAME="$_host"

printf 'sandbox env: profile=%s  WORKSPACE_NAME=%s\n' "$_prof" "${WORKSPACE_NAME:-<unset>}"
if [ -n "${WORKSPACE_NAME:-}" ]; then
  # Best-effort auth sanity: the profile must be able to mint a token at runtime.
  if command -v databricks >/dev/null 2>&1 && ! databricks current-user me -p "$_prof" >/dev/null 2>&1; then
    echo "note: 'databricks current-user me -p $_prof' failed — auth may still resolve at runtime, or run: databricks auth login -p $_prof"
  fi
  echo "ready — check with ./verify_sandbox.sh, then:  omnigent run . -p \"...\""
else
  echo "could not resolve the host for profile '$_prof' — set it manually:  export WORKSPACE_NAME=<workspace-host>"
fi
unset _prof _cfg _host
