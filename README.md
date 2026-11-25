# hyperagent-install

One command installs the latest hyperagent release, verifies its checksum, invokes its portable setup, prints the doctor report, and tells you what to restart. It builds nothing.

## Install

Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/AnEntrypoint/hyperagent-install/main/install.sh | sh
```

Windows PowerShell x64:

```powershell
irm https://raw.githubusercontent.com/AnEntrypoint/hyperagent-install/main/install.ps1 | iex
```

## What it does

1. Selects the artifact for the host: x64-linux, arm64-linux, x64-macos, arm64-macos or x64-windows. A host without a published artifact fails with the reason.
2. Downloads SHA256SUMS and that archive from https://github.com/AnEntrypoint/hyperagent/releases/download/latest/, refuses a checksum mismatch, and installs nothing when verification fails.
3. Checks the shipped layout: bin/hyperagent, bin/ccbridge, share/ccbridge/templates, share/ccbridge/web, share/hyperagent/gui/public, scripts, docs and .mcp.json.
4. Installs a versioned directory under the user data directory and points current at it. The previous version stays as a fallback. The user PATH gains the bin directory.
5. Runs hyperagent setup, which creates the project parent, chooses a free loopback port, persists the full MCP environment in a user-scope install manifest, registers the MCP server with those variables, and writes or verifies .mcp.json.
6. Runs hyperagent doctor, or setup --check when that is the shipped check command, and prints its report. A failed doctor rolls the install back.

Restart Claude Code after installation. An already-running session keeps its old MCP connection; a restarted session reads the user-scope registration and reports connected with the long tool timeout.

## Settings

| Variable | Meaning |
|---|---|
| HYPERAGENT_RELEASE_BASE | Release base URL; use a local fake release for witnesses. |
| HYPERAGENT_EXPECTED_VERSION | Require hyperagent --version to equal this version. |
| HYPERAGENT_TEMPLATES | Harness template directory passed to setup as CCBRIDGE_TEMPLATES. |
| CCBRIDGE_TEMPLATES | Harness template directory read by setup and doctor. |
| XDG_DATA_HOME | Linux data home; macOS uses Library/Application Support and Windows uses LOCALAPPDATA. |
| HYPERAGENT_WITNESS_DIR | Witness scratch directory; otherwise the tools use TMPDIR through mktemp. |

## Custom chlaude-compatible peers

Put a claude.json harness template in a directory and set HYPERAGENT_TEMPLATES to that directory before installation. The template argv should name your own chlaude-compatible wrapper and contain no --model flag. The wrapper reads the host chlaude export lines itself; keep its credentials out of the template, repository, logs and reports. The peer launch uses --model default, and unset AIRC_CLAUDE_MODEL and ORCH_CLAUDE_MODEL leave no conflicting --model appended by hyperagent.

After setup, doctor checks the persisted MCP environment, the project parent, the chosen port, the shipped resources and the absence of a conflicting model override. Restart Claude Code before using the peers.

## Verify and update

Run hyperagent doctor from a clean shell, or run the install command again to replace current with the latest release. The previous version remains available until the next successful update. A clean reinstall can remove the user data directory and run the install command again.

## Uninstall

Linux and macOS:

```sh
rm -rf "$HOME/.local/share/hyperagent" "$HOME/.local/bin/hyperagent"
```

On macOS replace the data directory with "$HOME/Library/Application Support/hyperagent". On Windows delete %LOCALAPPDATA%\hyperagent and remove its current\bin entry from the user PATH.

## Witnesses

POSIX hosts:

```sh
sh tools/syntax.sh && sh tools/witness.sh && sh tools/red.sh
```

Windows PowerShell:

```powershell
powershell -NoProfile -File tools/syntax.ps1; powershell -NoProfile -File tools/witness.ps1; powershell -NoProfile -File tools/red.ps1
```

The hosted install-witness workflow runs the same checks on Linux, macOS and Windows. Bad checksums, wrong artifacts, occupied ports without fallback, missing project parents, missing resources, stale MCP registrations, hardcoded host paths and conflicting model overrides each have a named red check.
