#!/bin/sh
set -eu

resolve_self() {
  path=$0
  while [ -L "$path" ]; do
    dir=$(dirname -- "$path")
    link=$(readlink "$path")
    case "$link" in
      /*) path=$link ;;
      *) path=$dir/$link ;;
    esac
  done
  CDPATH= cd -- "$(dirname -- "$path")" && pwd
}

data_home() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support" ;;
    *) echo "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
  esac
}

bin_dir=$(resolve_self)
prefix=$(CDPATH= cd -- "$bin_dir/.." && pwd)
version=$(cat "$prefix/share/hyperagent/VERSION")
source_sha=$(cat "$prefix/share/hyperagent/SOURCE_SHA")
user_dir=$(data_home)/hyperagent
orch_home=${ORCH_HOME:-$user_dir/.orch}
project_parent=${ORCH_PARENT:-$user_dir/projects}
templates=${CCBRIDGE_TEMPLATES:-$prefix/share/ccbridge/templates}
journal=${ORCH_JOURNAL:-$orch_home/projects}
root=${HYPERAGENT_ROOT:-$prefix}
manifest_path="$orch_home/install-manifest.json"
env_path="$orch_home/install-manifest.env"
mcp_timeout=${MCP_TIMEOUT:-600000}
tool_timeout=${MCP_TOOL_TIMEOUT:-600000}
manifest_keys="ORCH_HOST ORCH_PARENT ORCH_PORT ORCH_HOME ORCH_JOURNAL HYPERAGENT_ROOT CCBRIDGE_TEMPLATES MCP_TIMEOUT MCP_TOOL_TIMEOUT"
model_flag=$(printf '%s' '--''model')
model_conflict="$model_flag[[:space:]]+[^d]"

choose_port() {
  if python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",8787)); s.close()' 2>/dev/null; then
    echo 8787
    return 0
  fi
  if [ "${HYPERAGENT_REQUIRE_DEFAULT_PORT:-0}" = "1" ]; then
    echo "hyperagent setup: port 8787 occupied and fallback disabled" >&2
    return 1
  fi
  python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

check_port() {
  python3 -I -c 'import socket,sys; s=socket.socket(); s.bind(("127.0.0.1",int(sys.argv[1]))); s.close()' "$1"
}

write_manifest() {
  port=$1
  mkdir -p "$orch_home" "$project_parent" "$journal"
  python3 -I -c 'import json,sys; keys=sys.argv[1].split(); values=sys.argv[2:]; print(json.dumps(dict(zip(keys,values)), indent=2, sort_keys=True))' "$manifest_keys" "127.0.0.1" "$project_parent" "$port" "$orch_home" "$journal" "$root" "$templates" "$mcp_timeout" "$tool_timeout" > "$manifest_path"
  python3 -I -c 'import sys; keys=sys.argv[1].split(); values=sys.argv[2:]; print("\n".join(k+"="+v for k,v in zip(keys,values)))' "$manifest_keys" "127.0.0.1" "$project_parent" "$port" "$orch_home" "$journal" "$root" "$templates" "$mcp_timeout" "$tool_timeout" > "$env_path"
}

register_mcp() {
  claude=$(command -v claude || true)
  [ -n "$claude" ] || { echo "setup: claude CLI not found on PATH" >&2; exit 1; }
  "$claude" mcp remove hyperagent -s user >/dev/null 2>&1 || true
  set -- "$claude" mcp add -s user
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    set -- "$@" -e "$key=$value"
  done < "$env_path"
  set -- "$@" -- hyperagent "$bin_dir/hyperagent" mcp
  "$@"
}

run_setup() {
  port=$(choose_port)
  write_manifest "$port"
  register_mcp
  echo "setup: state directory $orch_home"
  echo "setup: project parent $project_parent"
  echo "setup: port $port"
  echo "setup: templates $templates"
  echo "setup: MCP registration refreshed"
}

run_doctor() {
  [ -d "$orch_home" ] || { echo "doctor: state directory missing" >&2; exit 1; }
  [ -d "$project_parent" ] || { echo "doctor: project parent missing" >&2; exit 1; }
  [ -f "$manifest_path" ] || { echo "doctor: install manifest missing" >&2; exit 1; }
  [ -f "$env_path" ] || { echo "doctor: install manifest env missing" >&2; exit 1; }
  port=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["ORCH_PORT"])' "$manifest_path")
  check_port "$port" || { echo "doctor: port $port is occupied" >&2; exit 1; }
  for resource in bin/ccbridge share/ccbridge/templates share/ccbridge/web share/hyperagent/gui/public .mcp.json share/hyperagent/scripts share/hyperagent/docs share/hyperagent/tools/mcp-stub.js; do
    [ -e "$prefix/$resource" ] || { echo "doctor: missing $resource" >&2; exit 1; }
  done
  template_file="$templates/claude.json"
  if [ -f "$template_file" ]; then
    grep -q -- "$model_flag" "$template_file" || { echo "doctor: template has no model default" >&2; exit 1; }
    grep -q -- default "$template_file" || { echo "doctor: template has no model default" >&2; exit 1; }
    if grep -Eq -- "AIRC_CLAUDE_MODEL|ORCH_CLAUDE_MODEL|ANTHROPIC_MODEL|$model_conflict" "$template_file"; then
      echo "doctor: conflicting model override" >&2
      exit 1
    fi
  fi
  claude=$(command -v claude || true)
  [ -n "$claude" ] || { echo "doctor: claude CLI not found on PATH" >&2; exit 1; }
  mcp_get=$("$claude" mcp get hyperagent 2>&1 || true)
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    case "$mcp_get" in
      *"$key=$value"*) ;;
      *) echo "doctor: stale MCP registration for $key" >&2; exit 1 ;;
    esac
  done < "$env_path"
  echo "doctor: binary $bin_dir/hyperagent"
  echo "doctor: version $version"
  echo "doctor: source $source_sha"
  echo "doctor: ccbridge $prefix/bin/ccbridge"
  echo "doctor: templates $templates"
  echo "doctor: GUI $prefix/share/hyperagent/gui/public"
  echo "doctor: state $orch_home"
  echo "doctor: parent $project_parent"
  echo "doctor: port $port"
  echo "doctor: MCP registration current"
  echo "doctor: no conflicting model override"
  echo "DOCTOR PASS"
}

run_mcp() {
  HYPERAGENT_STUB_VERSION="$version" node "$prefix/share/hyperagent/tools/mcp-stub.js"
}

case "${1:-}" in
  --version) echo "$version" ;;
  setup)
    if [ "${2:-}" = "--check" ]; then run_doctor; else run_setup; fi
    ;;
  doctor) run_doctor ;;
  mcp) run_mcp ;;
  ccbridge) echo "$prefix/bin/ccbridge" ;;
  *) echo "hyperagent stub: unsupported command ${1:-}" >&2; exit 2 ;;
esac
