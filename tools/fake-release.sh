#!/bin/sh
set -eu
release_dir="$1"
version="$2"

case "$(uname -s)" in Darwin) system=macos ;; *) system=linux ;; esac
case "$(uname -m)" in x86_64 | amd64) machine=x64 ;; *) machine=arm64 ;; esac
target="$machine-$system"
archive="hyperagent-$target.tar.gz"

rm -rf "$release_dir"
staging=$(mktemp -d)
mkdir -p "$release_dir" "$staging/hyperagent-$target/bin"
cat > "$staging/hyperagent-$target/bin/hyperagent" <<EOF
#!/bin/sh
case "\$1" in
  --version) echo "hyperagent $version" ;;
  setup) echo "setup ran with HOME=\$HOME" ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$staging/hyperagent-$target/bin/hyperagent"
tar -C "$staging" -czf "$release_dir/$archive" "hyperagent-$target"
rm -rf "$staging"
(cd "$release_dir" && sha256sum "$archive" > SHA256SUMS)
echo "$archive"
