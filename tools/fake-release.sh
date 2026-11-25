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
python3 -I -c '
import hashlib,json,sys
release_dir, archive, version, source_sha, target = sys.argv[1:6]
targets = ["arm64-linux", "arm64-macos", "x64-linux", "x64-macos", "x64-windows"]
build = version + "-23"
manifest_targets = {}
for name in targets:
    ext = "zip" if name == "x64-windows" else "tar.gz"
    manifest_targets[name] = {"asset": "hyperagent-" + build + "-" + name + "." + ext, "sha256": "0" * 64, "size": 1}
manifest = {"build": build, "sha": source_sha, "targets": manifest_targets}
open(release_dir + "/manifest.json", "w").write(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
actual = hashlib.sha256(open(release_dir + "/" + archive, "rb").read()).hexdigest()
lines = []
for name in targets:
    ext = "zip" if name == "x64-windows" else "tar.gz"
    stable = "hyperagent-" + name + "." + ext
    lines.append((actual if stable == archive else "0" * 64) + "  " + stable)
for name in targets:
    ext = "zip" if name == "x64-windows" else "tar.gz"
    lines.append("0" * 64 + "  hyperagent-" + build + "-" + name + "." + ext)
open(release_dir + "/SHA256SUMS", "w").write("\n".join(lines) + "\n")
' "$release_dir" "$archive" "$version" "${HYPERAGENT_SOURCE_SHA:-witness-sha}" "$target"
echo "$archive"
