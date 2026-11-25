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
    curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    fail "curl or wget is required"
  fi
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
templates_dir=${HYPERAGENT_TEMPLATES:-}
target=$(detect_target)
archive="hyperagent-$target.tar.gz"
install_root="$(data_home)/hyperagent"
versions_dir="$install_root/versions"
bin_dir="$HOME/.local/bin"
scratch=$(mktemp -d)
version_dir=""
previous=""
committed=0
trap 'rollback' EXIT

echo "downloading $archive from $release_base"
download "$release_base/SHA256SUMS" "$scratch/SHA256SUMS"
download "$release_base/$archive" "$scratch/$archive"

expected=$(awk -v name="$archive" '$2 == name { print $1 }' "$scratch/SHA256SUMS" | head -n 1)
[ -n "$expected" ] || fail "SHA256SUMS has no entry for $archive"
actual=$(sha256_of "$scratch/$archive")
[ "$expected" = "$actual" ] || fail "sha256 mismatch for $archive: expected $expected, got $actual; nothing was installed"

mkdir -p "$scratch/unpacked"
tar -xzf "$scratch/$archive" -C "$scratch/unpacked"
unpacked_dir="$scratch/unpacked/hyperagent-$target"
[ -x "$unpacked_dir/bin/hyperagent" ] || fail "the archive has no bin/hyperagent"
for resource in bin/ccbridge share/ccbridge/templates share/ccbridge/web share/hyperagent/gui/public .mcp.json share/hyperagent/scripts share/hyperagent/docs; do
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

if [ -n "$templates_dir" ]; then
  CCBRIDGE_TEMPLATES="$templates_dir"
  export CCBRIDGE_TEMPLATES
fi
"$exe" setup

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
