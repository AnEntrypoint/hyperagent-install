#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
grep -q 'Get-WindowsArchiveName' "$tools_dir/common.ps1" || { echo "FAIL: Windows archive helper missing"; exit 1; }
grep -q '\$archive = Get-WindowsArchiveName' "$tools_dir/red.ps1" || { echo "FAIL: Windows red check does not locate the archive"; exit 1; }
grep -q 'Test-Path -LiteralPath \$archivePath -PathType Leaf' "$tools_dir/red.ps1" || { echo "FAIL: Windows archive guard missing"; exit 1; }
test_line=$(grep -n 'Test-Path -LiteralPath \$archivePath -PathType Leaf' "$tools_dir/red.ps1" | cut -d: -f1)
read_line=$(grep -n 'ReadAllBytes' "$tools_dir/red.ps1" | cut -d: -f1)
[ "$test_line" -lt "$read_line" ] || { echo "FAIL: Windows archive guard follows the read"; exit 1; }
echo "RED PASS: Windows fake-release archive located before read"
