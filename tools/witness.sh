#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
. "$tools_dir/common.sh"
set_test_path
isolate_setup_env
work=$(work_dir)
server_pid=""
port_holder_pid=""
cleanup() {
  stop_pid "$server_pid"
  stop_pid "$port_holder_pid"
  rm -rf "$work"
}
trap 'cleanup' EXIT
home_dir="$work/home"
release_dir="$work/fake-latest"
template_dir="$work/templates"
expected_version=${HYPERAGENT_EXPECTED_VERSION:-1.0.0}
source_sha=${HYPERAGENT_SOURCE_SHA:-witness-sha}
export HYPERAGENT_EXPECTED_SOURCE_SHA="$source_sha"
mkdir -p "$home_dir"
make_template "$template_dir"
HYPERAGENT_SOURCE_SHA="$source_sha" "$tools_dir/fake-release.sh" "$release_dir" "$expected_version" > /dev/null
target_count=$(python3 -I -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["targets"]))' "$release_dir/manifest.json")
[ "$target_count" -eq 5 ] || { echo "FAIL: manifest has $target_count targets"; exit 1; }
checksum_count=$(wc -l < "$release_dir/SHA256SUMS" | tr -d ' ')
[ "$checksum_count" -eq 10 ] || { echo "FAIL: $checksum_count checksum lines"; exit 1; }
start_server "$release_dir" "$work/server.log"
port_holder_pid=$(hold_default_port "$work/holder.log")
export HOME="$home_dir"
export XDG_DATA_HOME="$home_dir/.local/share"
data_root="$(data_home)/hyperagent"
export PATH="$home_dir/.local/bin:$PATH"
export HYPERAGENT_RELEASE_BASE="http://127.0.0.1:$server_port"
export HYPERAGENT_EXPECTED_VERSION="$expected_version"
export HYPERAGENT_TEMPLATES="$template_dir"
export TMPDIR="$work"
sh "$tools_dir/../install.sh" > "$work/install1.log" 2>&1
grep -q "DOCTOR PASS" "$work/install1.log" || { echo "FAIL: doctor report missing"; cat "$work/install1.log"; exit 1; }
grep -q "Restart Claude Code" "$work/install1.log" || { echo "FAIL: restart note missing"; cat "$work/install1.log"; exit 1; }
[ "$(hyperagent --version)" = "$expected_version" ] || { echo "FAIL: version after install"; exit 1; }
[ -L "$home_dir/.local/bin/hyperagent" ] || { echo "FAIL: link missing"; exit 1; }
manifest="$data_root/.orch/install-manifest.json"
env_file="$data_root/.orch/install-manifest.env"
port=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["ORCH_PORT"])' "$manifest")
parent=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["ORCH_PARENT"])' "$manifest")
[ "$port" != "8787" ] || { echo "FAIL: no port fallback"; exit 1; }
[ -d "$parent" ] || { echo "FAIL: project parent missing"; exit 1; }
grep -F "$template_dir" "$env_file" > /dev/null || { echo "FAIL: custom template not persisted"; exit 1; }
check_mcp_env "$home_dir" "$env_file"
assert_connected "$home_dir"
stop_pid "$port_holder_pid"
port_holder_pid=""
HYPERAGENT_SOURCE_SHA="$source_sha" "$tools_dir/fake-release.sh" "$release_dir" 2.0.0 > /dev/null
HYPERAGENT_EXPECTED_VERSION=2.0.0 sh "$tools_dir/../install.sh" > "$work/install2.log" 2>&1
[ "$(hyperagent --version)" = "2.0.0" ] || { echo "FAIL: version after update"; exit 1; }
version_count=$(ls "$data_root/versions" | wc -l | tr -d ' ')
[ "$version_count" -eq 2 ] || { echo "FAIL: previous version not kept"; exit 1; }
HYPERAGENT_SOURCE_SHA="$source_sha" "$tools_dir/fake-release.sh" "$release_dir" 3.0.0 > /dev/null
HYPERAGENT_EXPECTED_VERSION=3.0.0 sh "$tools_dir/../install.sh" > "$work/install3.log" 2>&1
[ "$(hyperagent --version)" = "3.0.0" ] || { echo "FAIL: version after prune"; exit 1; }
version_count=$(ls "$data_root/versions" | wc -l | tr -d ' ')
[ "$version_count" -eq 2 ] || { echo "FAIL: older versions not pruned"; exit 1; }
HYPERAGENT_SOURCE_SHA="$source_sha" "$tools_dir/fake-release.sh" "$release_dir" "$expected_version" > /dev/null
rm -rf "$home_dir"
mkdir -p "$home_dir"
HYPERAGENT_EXPECTED_VERSION="$expected_version" sh "$tools_dir/../install.sh" > "$work/install-clean.log" 2>&1
[ "$(hyperagent --version)" = "$expected_version" ] || { echo "FAIL: version after clean reinstall"; exit 1; }
hyperagent doctor > "$work/doctor-clean.log" 2>&1
grep -q "DOCTOR PASS" "$work/doctor-clean.log" || { echo "FAIL: clean doctor"; cat "$work/doctor-clean.log"; exit 1; }
check_mcp_env "$home_dir" "$env_file"
assert_connected "$home_dir"
if grep -Eiq 'warning|failed|error' "$work"/install*.log; then
  echo "FAIL: unexpected warning, failure or error in install logs" >&2
  grep -Ein 'warning|failed|error' "$work"/install*.log >&2
  exit 1
fi
printf 'WITNESS PASS: %s %s install, doctor, port fallback, MCP env, connected, update, pruning, clean reinstall\n' "$expected_version" "$source_sha"
