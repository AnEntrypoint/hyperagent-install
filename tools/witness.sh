#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
work=${HYPERAGENT_WITNESS_DIR:-/workspace/tmp/hyperagent-release/witness}
release_dir="$work/fake-latest"
home_dir="$work/home"
rm -rf "$work"
mkdir -p "$work" "$home_dir"

"$tools_dir/fake-release.sh" "$release_dir" 1.0.0 > /dev/null
read -r server_pid port <<EOF
$("$tools_dir/serve.sh" "$release_dir" "$work/server.log")
EOF
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
export HOME="$home_dir"
export HYPERAGENT_RELEASE_BASE="http://127.0.0.1:$port"
export PATH="$home_dir/.local/bin:$PATH"
export XDG_DATA_HOME="$home_dir/.local/share"

sh "$tools_dir/../install.sh"
[ "$(hyperagent --version)" = "hyperagent 1.0.0" ] || { echo "FAIL: version after first install"; exit 1; }
[ -L "$home_dir/.local/bin/hyperagent" ] || { echo "FAIL: link missing"; exit 1; }
[ "$(ls "$XDG_DATA_HOME/hyperagent/versions" | wc -l)" -eq 1 ] || { echo "FAIL: expected one version"; exit 1; }

sleep 1
"$tools_dir/fake-release.sh" "$release_dir" 2.0.0 > /dev/null
sh "$tools_dir/../install.sh"
[ "$(hyperagent --version)" = "hyperagent 2.0.0" ] || { echo "FAIL: version after update"; exit 1; }
[ "$(ls "$XDG_DATA_HOME/hyperagent/versions" | wc -l)" -eq 2 ] || { echo "FAIL: previous version not kept"; exit 1; }

sleep 1
"$tools_dir/fake-release.sh" "$release_dir" 3.0.0 > /dev/null
sh "$tools_dir/../install.sh"
[ "$(ls "$XDG_DATA_HOME/hyperagent/versions" | wc -l)" -eq 2 ] || { echo "FAIL: older versions not pruned"; exit 1; }

echo "WITNESS PASS: installed, linked, version answered, setup ran, update kept the previous version"
