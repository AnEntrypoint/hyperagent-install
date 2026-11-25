#!/bin/sh
set -eu

fail() {
  echo "hyperagent install: $*" >&2
  exit 1
}

detect_target() {
  case "$(uname -s)" in
    Linux) system=linux ;;
    Darwin) system=macos ;;
    *) fail "unsupported system $(uname -s); on Windows use install.ps1" ;;
  esac
  case "$(uname -m)" in
    x86_64 | amd64) machine=x64 ;;
    aarch64 | arm64) machine=arm64 ;;
    *) fail "unsupported architecture $(uname -m)" ;;
  esac
  echo "$machine-$system"
}

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$2" "$1" || fail "download failed for $1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1" || fail "download failed for $1"
  else
    fail "curl or wget is required"
  fi
}

scratch_root() {
  if [ -n "${HYPERAGENT_SCRATCH:-}" ]; then
    echo "$HYPERAGENT_SCRATCH/hyperagent-install"
  else
    echo "${XDG_DATA_HOME:-$HOME/.local/share}/hyperagent-scratch"
  fi
}

validate_release() {
  python3 -I -c '
import json,sys
expected_sha = sys.argv[3]
manifest = json.load(open(sys.argv[1]))
targets = ["arm64-linux", "arm64-macos", "x64-linux", "x64-macos", "x64-windows"]
if manifest.get("sha") != expected_sha:
    sys.exit("partial release: manifest SHA " + str(manifest.get("sha")) + " does not match " + expected_sha)
manifest_targets = manifest.get("targets", {})
if sorted(manifest_targets) != targets:
    sys.exit("partial release: expected five targets, found " + ",".join(sorted(manifest_targets)))
build = manifest.get("build", "")
if not build:
    sys.exit("partial release: manifest has no build")
stable = []
versioned = []
for target in targets:
    ext = "zip" if target == "x64-windows" else "tar.gz"
    stable.append("hyperagent-" + target + "." + ext)
    asset = manifest_targets[target].get("asset", "")
    if not asset:
        sys.exit("partial release: missing asset for " + target)
    versioned.append(asset)
names = []
for line in open(sys.argv[2]):
    parts = line.split()
    if len(parts) >= 2:
        names.append(parts[1])
expected_names = stable + versioned
missing = [name for name in expected_names if name not in names]
if missing:
    sys.exit("partial release: missing checksum for " + missing[0])
if len(names) != 10 or len(set(names)) != 10:
    sys.exit("partial release: expected ten checksum lines, found " + str(len(names)))
' "$scratch/manifest.json" "$scratch/SHA256SUMS" "$expected_source_sha" || fail "partial release rejected"
}

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | cut -d' ' -f1
  else
    python3 -I -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
  fi
}

data_home() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support" ;;
    *) echo "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
  esac
}

replace_link() {
  source_link=$1
  destination=$2
  if mv -f -h "$source_link" "$destination" 2>/dev/null; then return 0; fi
  if mv -fT "$source_link" "$destination" 2>/dev/null; then return 0; fi
  rm -rf "$destination"
  mv -f "$source_link" "$destination"
}

rollback() {
  if [ "$committed" -eq 0 ] && [ -n "$version_dir" ] && [ -d "$version_dir" ]; then
    if [ -n "$previous" ]; then
      ln -sfn "$previous" "$install_root/current.new" || true
      replace_link "$install_root/current.new" "$install_root/current" || true
    else
      rm -rf "$install_root/current" || true
    fi
    rm -rf "$version_dir" || true
  fi
  if [ -n "$scratch" ] && [ -d "$scratch" ]; then
    rm -rf "$scratch" || true
  fi
}

release_base=${HYPERAGENT_RELEASE_BASE:-https://github.com/AnEntrypoint/hyperagent/releases/download/latest}
expected_version=${HYPERAGENT_EXPECTED_VERSION:-}
expected_source_sha=${HYPERAGENT_EXPECTED_SOURCE_SHA:-${HYPERAGENT_SOURCE_SHA:-b79a2428a122db7087dd660df55b7fca64922cc1}}
templates_dir=${HYPERAGENT_TEMPLATES:-}
target=$(detect_target)
archive="hyperagent-$target.tar.gz"
install_root="$(data_home)/hyperagent"
versions_dir="$install_root/versions"
bin_dir="$HOME/.local/bin"
scratch_root_dir=$(scratch_root)
mkdir -p "$scratch_root_dir"
scratch=$(mktemp -d "$scratch_root_dir/hyperagent-install.XXXXXX")
version_dir=""
previous=""
committed=0
trap 'rollback' EXIT

echo "downloading $archive from $release_base"
download "$release_base/manifest.json" "$scratch/manifest.json"
download "$release_base/SHA256SUMS" "$scratch/SHA256SUMS"
validate_release

expected=$(awk -v name="$archive" '$2 == name { print $1 }' "$scratch/SHA256SUMS" | head -n 1)
[ -n "$expected" ] || fail "SHA256SUMS has no entry for $archive"
download "$release_base/$archive" "$scratch/$archive"
actual=$(sha256_of "$scratch/$archive")
[ "$expected" = "$actual" ] || fail "sha256 mismatch for $archive: expected $expected, got $actual; nothing was installed"

mkdir -p "$scratch/unpacked"
tar -xzf "$scratch/$archive" -C "$scratch/unpacked"
unpacked_dir="$scratch/unpacked/hyperagent-$target"
[ -x "$unpacked_dir/bin/hyperagent" ] || fail "the archive has no bin/hyperagent"
for resource in bin/ccbridge share/ccbridge/templates share/ccbridge/web share/hyperagent/gui/public .mcp.json scripts docs tools; do
  [ -e "$unpacked_dir/$resource" ] || fail "the archive has no $resource"
done

version_name="$(date -u +%Y%m%d%H%M%S)-$$"
version_dir="$versions_dir/$version_name"
mkdir -p "$versions_dir" "$bin_dir"
mv "$unpacked_dir" "$version_dir"

previous=""
if [ -L "$install_root/current" ]; then
  previous=$(readlink "$install_root/current")
fi
ln -sfn "$version_dir" "$install_root/current.new"
replace_link "$install_root/current.new" "$install_root/current"
ln -sfn "$install_root/current/bin/hyperagent" "$bin_dir/hyperagent"
exe="$install_root/current/bin/hyperagent"

version_output=$("$exe" --version)
if [ -n "$expected_version" ] && [ "$version_output" != "$expected_version" ]; then
  fail "installed version $version_output does not match expected $expected_version"
fi
printf 'installed %s\n' "$version_name"
printf '%s\n' "$version_output"

data_root="$(data_home)/hyperagent"
state_home=${HYPERAGENT_HOME:-$data_root/.orch}
project_parent=${HYPERAGENT_PARENT:-$data_root/projects}
journal=${HYPERAGENT_JOURNAL:-$state_home/projects}
templates=${HYPERAGENT_TEMPLATES:-$install_root/current/share/ccbridge/templates}
preferred_port=${HYPERAGENT_PORT:-8787}
CCBRIDGE_TEMPLATES="$templates"
export CCBRIDGE_TEMPLATES
"$exe" setup --parent "$project_parent" --home "$state_home" --journal "$journal" --templates "$templates" --port "$preferred_port"

if "$exe" doctor > "$scratch/doctor.log" 2>&1; then
  cat "$scratch/doctor.log"
elif "$exe" setup --check > "$scratch/doctor-check.log" 2>&1; then
  cat "$scratch/doctor-check.log"
else
  cat "$scratch/doctor.log" >&2
  cat "$scratch/doctor-check.log" >&2
  fail "doctor report failed"
fi

for old in "$versions_dir"/*; do
  [ -d "$old" ] || continue
  [ "$old" = "$version_dir" ] && continue
  [ "$old" = "$previous" ] && continue
  rm -rf "$old"
done

committed=1
printf '\n'
printf '%s\n' 'Restart Claude Code so the hyperagent MCP registration reloads.'
case ":$PATH:" in
  *":$bin_dir:"*) ;;
  *) printf '%s\n' "Add $bin_dir to your PATH." ;;
esac
printf '%s\n' 'Use CCBRIDGE_TEMPLATES before setup for a chlaude-compatible harness and keep --model default.'
