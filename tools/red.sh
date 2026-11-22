#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
work=${HYPERAGENT_WITNESS_DIR:-/workspace/tmp/hyperagent-release/red}
release_dir="$work/fake-latest"
home_dir="$work/home"
rm -rf "$work"
mkdir -p "$work" "$home_dir"

archive=$("$tools_dir/fake-release.sh" "$release_dir" 1.0.0)
printf 'X' | dd of="$release_dir/$archive" bs=1 seek=10 conv=notrunc 2>/dev/null
read -r server_pid port <<EOF
$("$tools_dir/serve.sh" "$release_dir" "$work/server.log")
EOF
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
export HOME="$home_dir"
export HYPERAGENT_RELEASE_BASE="http://127.0.0.1:$port"
export XDG_DATA_HOME="$home_dir/.local/share"

if sh "$tools_dir/../install.sh" > "$work/install.log" 2>&1; then
  echo "RED FAIL: install.sh accepted a corrupted archive"
  exit 1
fi
grep -q "sha256 mismatch" "$work/install.log" || { echo "RED FAIL: no mismatch message"; cat "$work/install.log"; exit 1; }
[ ! -e "$XDG_DATA_HOME/hyperagent" ] && [ ! -e "$home_dir/.local/bin/hyperagent" ] || { echo "RED FAIL: something was installed"; exit 1; }
echo "RED PASS: corrupted archive refused and nothing installed"
