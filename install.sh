#!/bin/sh
set -eu

release_base="${HYPERAGENT_RELEASE_BASE:-https://github.com/AnEntrypoint/hyperagent/releases/download/latest}"

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
    fail "sha256sum or shasum is required"
  fi
}

data_home() {
  case "$(uname -s)" in
    Darwin) echo "$HOME/Library/Application Support" ;;
    *) echo "${XDG_DATA_HOME:-$HOME/.local/share}" ;;
  esac
}

target=$(detect_target)
archive="hyperagent-$target.tar.gz"
install_root="$(data_home)/hyperagent"
versions_dir="$install_root/versions"
bin_dir="$HOME/.local/bin"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

echo "downloading $archive from $release_base"
download "$release_base/SHA256SUMS" "$scratch/SHA256SUMS"
download "$release_base/$archive" "$scratch/$archive"

expected=$(awk -v name="$archive" '$2 == name { print $1 }' "$scratch/SHA256SUMS")
[ -n "$expected" ] || fail "SHA256SUMS has no entry for $archive"
actual=$(sha256_of "$scratch/$archive")
[ "$expected" = "$actual" ] || fail "sha256 mismatch for $archive: expected $expected, got $actual; nothing was installed"

mkdir -p "$scratch/unpacked"
tar -xzf "$scratch/$archive" -C "$scratch/unpacked"
unpacked_dir="$scratch/unpacked/hyperagent-$target"
[ -x "$unpacked_dir/bin/hyperagent" ] || fail "the archive has no bin/hyperagent"

version_name=$(date -u +%Y%m%d%H%M%S)
mkdir -p "$versions_dir" "$bin_dir"
mv "$unpacked_dir" "$versions_dir/$version_name"

previous=""
if [ -L "$install_root/current" ]; then
  previous=$(readlink "$install_root/current")
fi
ln -sfn "$versions_dir/$version_name" "$install_root/current.new"
mv -f -h "$install_root/current.new" "$install_root/current" 2>/dev/null || mv -fT "$install_root/current.new" "$install_root/current"

for old in "$versions_dir"/*; do
  [ -d "$old" ] || continue
  [ "$old" = "$versions_dir/$version_name" ] && continue
  [ "$old" = "$previous" ] && continue
  rm -rf "$old"
done

ln -sfn "$install_root/current/bin/hyperagent" "$bin_dir/hyperagent"

echo "installed $version_name"
"$bin_dir/hyperagent" --version
"$bin_dir/hyperagent" setup

case ":$PATH:" in
  *":$bin_dir:"*) path_note="" ;;
  *) path_note="Add $bin_dir to your PATH." ;;
esac

echo
echo "What is left to do:"
[ -n "$path_note" ] && echo "  - $path_note"
echo "  - Install the claude CLI if you have not: https://docs.claude.com/en/docs/claude-code"
echo "  - Run: hyperagent --help"
