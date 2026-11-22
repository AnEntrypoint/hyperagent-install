# hyperagent-install

One-step installer for the latest hyperagent release. It downloads a prebuilt binary, verifies its sha256 and sets it up. It builds nothing.

## Install

Linux and macOS:

```sh
curl -fsSL https://raw.githubusercontent.com/AnEntrypoint/hyperagent-install/main/install.sh | sh
```

Windows PowerShell (x64):

```powershell
irm https://raw.githubusercontent.com/AnEntrypoint/hyperagent-install/main/install.ps1 | iex
```

## What it does

1. Detects the system and architecture: x64-linux, arm64-linux, arm64-macos, x64-macos or x64-windows.
2. Downloads SHA256SUMS and the archive from https://github.com/AnEntrypoint/hyperagent/releases/download/latest/ and refuses to install if the sha256 does not match.
3. Unpacks into a versions directory under the user data directory (`~/.local/share/hyperagent`, `~/Library/Application Support/hyperagent` or `%LOCALAPPDATA%\hyperagent`) and points `current` at it. The previous version is kept.
4. Puts `hyperagent` on your path: a link in `~/.local/bin`, or the user PATH on Windows.
5. Runs `hyperagent setup`, which creates the state directory and registers the MCP server with the claude CLI.

Set `HYPERAGENT_RELEASE_BASE` to download from another base URL.

## Update

Run the install command again. The new version becomes current and the one before it stays as a fallback.

## Uninstall

Linux and macOS:

```sh
rm -rf ~/.local/share/hyperagent ~/.local/bin/hyperagent
```

On macOS the data directory is `~/Library/Application Support/hyperagent`. On Windows delete `%LOCALAPPDATA%\hyperagent` and remove its `current\bin` entry from the user PATH.

## Install separately

The claude CLI. Setup reports plainly when it is missing, and you can run `hyperagent setup` again after installing it.
