#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
release_dir=$1
version=$2
target=${3:-}
if [ -z "$target" ]; then
  case "$(uname -s)" in Darwin) system=macos ;; *) system=linux ;; esac
  case "$(uname -m)" in x86_64 | amd64) machine=x64 ;; *) machine=arm64 ;; esac
  target="$machine-$system"
fi
archive="hyperagent-$target.tar.gz"
rm -rf "$release_dir"
mkdir -p "$release_dir"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
layout="$staging/hyperagent-$target"
mkdir -p "$layout/bin" "$layout/share/ccbridge/templates" "$layout/share/ccbridge/web" "$layout/share/hyperagent/gui/public" "$layout/share/hyperagent/tools" "$layout/scripts" "$layout/docs" "$layout/tools"
cp "$tools_dir/hyperagent-stub.sh" "$layout/bin/hyperagent"
chmod +x "$layout/bin/hyperagent"
printf '#!/bin/sh\nexit 0\n' > "$layout/bin/ccbridge"
chmod +x "$layout/bin/ccbridge"
cp "$tools_dir/mcp-stub.js" "$layout/share/hyperagent/tools/mcp-stub.js"
printf '%s\n' "$version" > "$layout/share/hyperagent/VERSION"
printf '%s\n' "${HYPERAGENT_SOURCE_SHA:-witness-sha}" > "$layout/share/hyperagent/SOURCE_SHA"
printf '<html></html>\n' > "$layout/share/ccbridge/web/index.html"
printf '<html></html>\n' > "$layout/share/hyperagent/gui/public/index.html"
printf '%s\n' '{"mcpServers":{"hyperagent":{"command":"build/hyperagent","args":["mcp"]}}}' > "$layout/.mcp.json"
printf '%s\n' 'placeholder' > "$layout/scripts/placeholder"
printf '%s\n' 'placeholder' > "$layout/docs/placeholder"
printf '%s\n' 'placeholder' > "$layout/tools/placeholder"
printf '%s\n' '{"default": true, "argv": ["chlaude-peer"], "ready": ["Claude Code"], "busy": ["esc to interrupt"], "transcript": {"kind": "claude-jsonl", "root": "{home}/.claude/projects"}}' > "$layout/share/ccbridge/templates/claude.json"
tar -C "$staging" -czf "$release_dir/$archive" "hyperagent-$target"
python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest(), sys.argv[2])' "$release_dir/$archive" "$archive" > "$release_dir/SHA256SUMS"
echo "$archive"
