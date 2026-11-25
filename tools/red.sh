#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
. "$tools_dir/common.sh"
set_test_path
isolate_setup_env
work=$(work_dir)
server_pid=""
port_holder_pid=""
dynamic_pid=""
cleanup() {
  stop_pid "$server_pid"
  stop_pid "$port_holder_pid"
  stop_pid "$dynamic_pid"
  rm -rf "$work"
}
trap 'cleanup' EXIT
home_dir="$work/home"
release_dir="$work/fake-latest"
template_dir="$work/templates"
source_sha=${HYPERAGENT_SOURCE_SHA:-witness-sha}
make_template "$template_dir"
fresh_home() {
  rm -rf "$home_dir"
  mkdir -p "$home_dir"
}
valid_release() {
  HYPERAGENT_SOURCE_SHA="$source_sha" "$tools_dir/fake-release.sh" "$release_dir" 1.0.0 > /dev/null
}
install_valid() {
  HYPERAGENT_EXPECTED_VERSION=1.0.0 sh "$tools_dir/../install.sh" > "$1" 2>&1
}
valid_release
start_server "$release_dir" "$work/server.log"
export HOME="$home_dir"
export XDG_DATA_HOME="$home_dir/.local/share"
export PATH="$home_dir/.local/bin:$PATH"
export HYPERAGENT_RELEASE_BASE="http://127.0.0.1:$server_port"
export HYPERAGENT_TEMPLATES="$template_dir"
export TMPDIR="$work"
fresh_home
archive=$(awk 'NR==1 { print $2 }' "$release_dir/SHA256SUMS")
printf 'X' | dd of="$release_dir/$archive" bs=1 seek=10 conv=notrunc 2>/dev/null
if HYPERAGENT_EXPECTED_VERSION=1.0.0 sh "$tools_dir/../install.sh" > "$work/bad-checksum.log" 2>&1; then
  echo "RED FAIL: install.sh accepted a corrupted archive" >&2
  exit 1
fi
grep -q "sha256 mismatch" "$work/bad-checksum.log" || { echo "RED FAIL: no mismatch message"; cat "$work/bad-checksum.log"; exit 1; }
[ ! -e "$XDG_DATA_HOME/hyperagent" ] && [ ! -e "$home_dir/.local/bin/hyperagent" ] || { echo "RED FAIL: something was installed"; exit 1; }
echo "RED PASS: corrupted archive refused and nothing installed"
fresh_home
HYPERAGENT_SOURCE_SHA="$source_sha" "$tools_dir/fake-release.sh" "$release_dir" 1.0.0 arm64-windows > /dev/null
if HYPERAGENT_EXPECTED_VERSION=1.0.0 sh "$tools_dir/../install.sh" > "$work/wrong-target.log" 2>&1; then
  echo "RED FAIL: install.sh accepted the wrong artifact" >&2
  exit 1
fi
grep -q "SHA256SUMS has no entry" "$work/wrong-target.log" || { echo "RED FAIL: no wrong artifact message"; cat "$work/wrong-target.log"; exit 1; }
[ ! -e "$XDG_DATA_HOME/hyperagent" ] && [ ! -e "$home_dir/.local/bin/hyperagent" ] || { echo "RED FAIL: wrong artifact installed"; exit 1; }
echo "RED PASS: wrong OS or architecture artifact refused"
fresh_home
valid_release
port_holder_pid=$(hold_default_port "$work/holder.log")
if HYPERAGENT_EXPECTED_VERSION=1.0.0 HYPERAGENT_REQUIRE_DEFAULT_PORT=1 sh "$tools_dir/../install.sh" > "$work/occupied-port.log" 2>&1; then
  echo "RED FAIL: occupied default port was accepted without fallback" >&2
  exit 1
fi
grep -q "port 8787 occupied and fallback disabled" "$work/occupied-port.log" || { echo "RED FAIL: no occupied port message"; cat "$work/occupied-port.log"; exit 1; }
stop_pid "$port_holder_pid"
port_holder_pid=""
echo "RED PASS: occupied port fails visibly without fallback"
fresh_home
valid_release
install_valid "$work/valid.log"
manifest="$XDG_DATA_HOME/hyperagent/.orch/install-manifest.json"
parent=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["ORCH_PARENT"])' "$manifest")
rm -rf "$parent"
if hyperagent doctor > "$work/missing-parent.log" 2>&1; then
  echo "RED FAIL: missing project parent was accepted" >&2
  exit 1
fi
grep -q "project parent missing" "$work/missing-parent.log" || { echo "RED FAIL: no missing parent message"; cat "$work/missing-parent.log"; exit 1; }
echo "RED PASS: missing project parent fails doctor"
fresh_home
valid_release
install_valid "$work/valid-resource.log"
rm -f "$XDG_DATA_HOME/hyperagent/current/.mcp.json"
if hyperagent doctor > "$work/missing-resource.log" 2>&1; then
  echo "RED FAIL: missing resource was accepted" >&2
  exit 1
fi
grep -q "missing .mcp.json" "$work/missing-resource.log" || { echo "RED FAIL: no missing resource message"; cat "$work/missing-resource.log"; exit 1; }
echo "RED PASS: missing shipped resource fails doctor"
fresh_home
valid_release
install_valid "$work/valid-mcp.log"
claude mcp remove hyperagent -s user >/dev/null 2>&1 || true
claude mcp add -s user hyperagent -- "$(command -v hyperagent)" mcp >/dev/null 2>&1
if hyperagent doctor > "$work/stale-mcp.log" 2>&1; then
  echo "RED FAIL: stale MCP registration was accepted" >&2
  exit 1
fi
grep -q "stale MCP registration" "$work/stale-mcp.log" || { echo "RED FAIL: no stale MCP message"; cat "$work/stale-mcp.log"; exit 1; }
echo "RED PASS: stale MCP registration fails doctor"
fresh_home
valid_release
install_valid "$work/valid-collision.log"
port=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["ORCH_PORT"])' "$manifest")
python3 -I -c 'import socket,sys,time; s=socket.socket(); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(); print("ready", flush=True); time.sleep(3600)' "$port" > "$work/collision-holder.log" 2>&1 &
dynamic_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  if grep -q ready "$work/collision-holder.log" >/dev/null 2>&1; then break; fi
  sleep 0.1
done
if hyperagent doctor > "$work/port-collision.log" 2>&1; then
  echo "RED FAIL: port collision was accepted" >&2
  exit 1
fi
grep -q "port $port is occupied" "$work/port-collision.log" || { echo "RED FAIL: no port collision message"; cat "$work/port-collision.log"; exit 1; }
stop_pid "$dynamic_pid"
dynamic_pid=""
echo "RED PASS: port collision fails doctor"
fresh_home
valid_release
if HYPERAGENT_EXPECTED_VERSION=wrong sh "$tools_dir/../install.sh" > "$work/wrong-version.log" 2>&1; then
  echo "RED FAIL: wrong installed version was accepted" >&2
  exit 1
fi
grep -q "does not match expected" "$work/wrong-version.log" || { echo "RED FAIL: no version mismatch message"; cat "$work/wrong-version.log"; exit 1; }
echo "RED PASS: wrong installed version refused"
sh "$tools_dir/syntax.sh" > "$work/syntax.log" 2>&1
grep -q "SYNTAX PASS" "$work/syntax.log" || { echo "RED FAIL: portability syntax check failed"; cat "$work/syntax.log"; exit 1; }
echo "RED PASS: hardcoded path, model override and token checks"
echo "RED PASS: bad checksum, wrong artifact, occupied port, missing parent, missing resource, stale MCP, port collision, wrong version and portability"
