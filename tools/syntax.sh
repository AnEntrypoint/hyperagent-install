#!/bin/sh
set -eu
tools_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$tools_dir/.." && pwd)
sh -n "$repo_dir/install.sh" "$tools_dir"/*.sh "$tools_dir/claude"
if command -v bash >/dev/null 2>&1; then
  bash -n "$repo_dir/install.sh" "$tools_dir"/*.sh "$tools_dir/claude"
fi
node --check "$tools_dir/mcp-stub.js"
bad_paths=$(printf '%s|%s|%s|%s' '/work''space' '/config/work''space' '/data/work''space' '/''tmp')
model_flag=$(printf '%s' '--''model')
model_default="$model_flag default"
token_prefix=$(printf '%s' 'sk-ant''-')
auth_assignment=$(printf '%s' 'ANTHROPIC_AUTH''_TOKEN=')
scan_paths="$repo_dir/install.sh $repo_dir/install.ps1 $repo_dir/README.md $repo_dir/docs $repo_dir/tools $repo_dir/.github"
if grep -R -n -E --exclude-dir=.git --exclude-dir=.gm --exclude-dir=.agentplug-kv -- "$bad_paths" $scan_paths; then
  echo "SYNTAX FAIL: hardcoded host path" >&2
  exit 1
fi
if grep -R -n -F --exclude-dir=.git --exclude-dir=.gm --exclude-dir=.agentplug-kv -- "$model_flag" $scan_paths | grep -v -F -- "$model_default"; then
  echo "SYNTAX FAIL: conflicting model override" >&2
  exit 1
fi
if grep -R -n -F --exclude-dir=.git --exclude-dir=.gm --exclude-dir=.agentplug-kv -- "$token_prefix" $scan_paths; then
  echo "SYNTAX FAIL: credential token in repository" >&2
  exit 1
fi
if grep -R -n -F --exclude-dir=.git --exclude-dir=.gm --exclude-dir=.agentplug-kv -- "$auth_assignment" $scan_paths; then
  echo "SYNTAX FAIL: credential assignment in repository" >&2
  exit 1
fi
if command -v pwsh >/dev/null 2>&1; then
  pwsh -NoProfile -File "$tools_dir/syntax.ps1"
else
  printf '%s\n' 'PowerShell parser is covered by the Windows CI runner.'
fi
printf '%s\n' 'SYNTAX PASS: shell, node, portability and model checks'
