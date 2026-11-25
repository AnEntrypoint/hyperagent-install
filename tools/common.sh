tools_common_dir=$(cd "$(dirname "$0")" && pwd)

work_dir() {
  if [ -n "${HYPERAGENT_WITNESS_DIR:-}" ]; then
    work=$HYPERAGENT_WITNESS_DIR
    rm -rf "$work"
    mkdir -p "$work"
  else
    scratch_root=${HYPERAGENT_SCRATCH:-${XDG_DATA_HOME:-$HOME/.local/share}/hyperagent-scratch}
    mkdir -p "$scratch_root/hyperagent-install"
    work=$(mktemp -d "$scratch_root/hyperagent-install/witness.XXXXXX")
  fi
  echo "$work"
}

start_server() {
  release_dir=$1
  log=$2
  read -r server_pid server_port <<EOF
$("$tools_common_dir/serve.sh" "$release_dir" "$log")
EOF
}

hold_default_port() {
  holder_log=$1
  holder_pid=""
  if python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",8787)); s.close()' >/dev/null 2>&1; then
    python3 -I -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",8787)); s.listen(); print("ready", flush=True); time.sleep(3600)' > "$holder_log" 2>&1 &
    holder_pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
      if grep -q ready "$holder_log" >/dev/null 2>&1; then break; fi
      sleep 0.1
    done
    grep -q ready "$holder_log" || { echo "FAIL: could not occupy default port" >&2; return 1; }
  fi
  echo "$holder_pid"
}

stop_pid() {
  pid=$1
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
}

make_template() {
  template_dir=$1
  mkdir -p "$template_dir"
  printf '%s\n' '{"default": true, "argv": ["chlaude-peer"], "ready": ["Claude Code"], "busy": ["esc to interrupt"], "transcript": {"kind": "claude-jsonl", "root": "{home}/.claude/projects"}}' > "$template_dir/claude.json"
}

check_mcp_env() {
  home_dir=$1
  env_file=$2
  mcp_get=$(HOME="$home_dir" claude mcp get hyperagent 2>&1 || true)
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    case "$mcp_get" in
      *"$key=$value"*) ;;
      *) echo "FAIL: MCP config missing $key" >&2; return 1 ;;
    esac
  done < "$env_file"
}

assert_connected() {
  home_dir=$1
  mcp_list=$(HOME="$home_dir" claude mcp list 2>&1 || true)
  case "$mcp_list" in
    *Connected*) ;;
    *) echo "FAIL: MCP registration not connected" >&2; echo "$mcp_list" >&2; return 1 ;;
  esac
}
set_test_path() {
  if [ "${HYPERAGENT_REAL_CLAUDE:-0}" != "1" ]; then
    PATH="$tools_common_dir:$PATH"
    export PATH
  fi
}
isolate_setup_env() {
  unset ORCH_HOME ORCH_PARENT ORCH_PORT ORCH_JOURNAL HYPERAGENT_ROOT CCBRIDGE_TEMPLATES MCP_TIMEOUT MCP_TOOL_TIMEOUT HYPERAGENT_REQUIRE_DEFAULT_PORT ORCH_CLAUDE_MODEL AIRC_CLAUDE_MODEL || true
}
data_home() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support" ;;
    *) echo "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
  esac
}

make_partial_release() {
  python3 -I -c '
import json,sys
release_dir = sys.argv[1]
path = release_dir + "/manifest.json"
manifest = json.load(open(path))
manifest["targets"].pop("x64-macos", None)
open(path, "w").write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
lines = []
for line in open(release_dir + "/SHA256SUMS"):
    parts = line.split()
    if len(parts) >= 2 and "x64-macos" not in parts[1]:
        lines.append(line.rstrip("\n"))
open(release_dir + "/SHA256SUMS", "w").write("\n".join(lines) + "\n")
' "$1"
}

make_missing_checksum_release() {
  python3 -I -c '
import sys
release_dir = sys.argv[1]
lines = []
for line in open(release_dir + "/SHA256SUMS"):
    parts = line.split()
    if len(parts) >= 2 and parts[1] != "hyperagent-x64-macos.tar.gz":
        lines.append(line.rstrip("\n"))
open(release_dir + "/SHA256SUMS", "w").write("\n".join(lines) + "\n")
' "$1"
}

host_archive() {
  case "$(uname -s)" in
    Darwin) system=macos ;;
    *) system=linux ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) machine=x64 ;;
    *) machine=arm64 ;;
  esac
  echo "hyperagent-$machine-$system.tar.gz"
}
