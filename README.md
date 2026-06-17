# Claude Desktop Dual Launcher (Windows)

Run **two (or more) Claude Desktop accounts side by side** on Windows — each
with its own login, chat history, and local state. Useful when you have two
Pro subscriptions, want a clean work/personal split, or you've hit a usage
limit and want to switch to your other account without logging out.

> **Platform:** Windows only (v1). macOS/Linux support is on the roadmap — the
> underlying technique works there too, but the paths and shortcut mechanics
> differ.

> **TL;DR of the trick:** Claude Desktop is an Electron app. Electron honors
> `--user-data-dir=<path>` to redirect all per-user state (OAuth tokens, chat
> history, window state) into a separate directory. Launching Claude with a
> custom `user-data-dir` creates an independent instance. Same technique used by
> Discord, Slack, VS Code, etc.

---

## Install (as a Claude Code skill)

If you use [Claude Code](https://claude.com/claude-code) (the CLI/desktop coding
agent), drop this whole folder into your skills directory:

```powershell
# from inside the cloned repo:
$dest = "$env:USERPROFILE\.claude\skills\claude-desktop-dual-launcher"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
Copy-Item -Path ".\*" -Destination $dest -Recurse -Force
```

Then in any Claude Code session, ask the agent something like:

> *"Set up a second Claude Desktop instance for my work account."*

The skill auto-triggers, asks for an instance name, runs the setup, and reports
back. You can also invoke it directly: `/claude-desktop-dual-launcher work`.

## Install (standalone, without Claude Code)

Just clone the repo and run the PowerShell script directly:

```powershell
git clone https://github.com/VITASID57/Claude-code-desktop-dual-launcher.git
cd Claude-code-desktop-dual-launcher
powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 -InstanceName "work"
```

That's it. A blank Claude window opens for you to log in with the second
account, and a `Claude (work).lnk` shortcut appears on your desktop.

---

## What it creates

After running `setup.ps1 -InstanceName work`:

| Path | Purpose |
|---|---|
| `%APPDATA%\Claude-work\` | The new instance's user-data-dir (OAuth, chat history, etc.) |
| `%USERPROFILE%\.claude-dual-launcher\launch-work.ps1` | Self-healing launcher (survives Claude updates) |
| `Desktop\Claude (work).lnk` | Desktop shortcut, double-click to launch |

The original Claude Desktop (launched from the Start menu / pinned taskbar
icon) is unchanged — it keeps using the default `%APPDATA%\Claude\`.

## Usage

- **Original account**: open Claude Desktop the normal way (Start menu / taskbar).
- **Second account**: double-click `Claude (work).lnk` on the desktop.
- **Both at once**: do both. They are completely independent processes.

You can also log out / log in inside each instance freely. The "instance" is
just an isolated storage location; which account is logged into it is up to you.

> ⚠️ **Don't log in to the same account in both instances simultaneously.**
> Anthropic's sessions list will show two clients online for one account, which
> may trigger a security/risk review.

## When Claude Desktop updates

The desktop shortcut hardcodes the current Claude.exe path including its
version number (e.g. `Claude_1.12603.1.0_x64__...`). When Claude updates, the
version number changes and the shortcut breaks.

Two fixes:

1. **Run the self-healing launcher directly.** Right-click
   `%USERPROFILE%\.claude-dual-launcher\launch-<name>.ps1` → *Run with
   PowerShell*. This script scans `WindowsApps\Claude_*` at runtime, so it
   always finds the newest version.

2. **Re-run setup** to refresh the shortcut:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1 -InstanceName "work" -Force
   ```

## Adding more instances

```powershell
.\scripts\setup.ps1 -InstanceName "personal"
.\scripts\setup.ps1 -InstanceName "client-acme"
```

Each name creates an independent `Claude-<name>` data directory and its own
shortcut.

## Removing an instance

```powershell
.\scripts\uninstall.ps1 -InstanceName "work"
```

Removes the desktop shortcut and launcher. Asks before deleting the
user-data-dir (so chat history isn't lost by accident). Pass `-KeepUserData` to
keep the data unconditionally; pass `-Force` to skip prompts.

---

## How it works under the hood

1. **Locate Claude.exe.** Claude Desktop installs as an MSIX package under
   `C:\Program Files\WindowsApps\Claude_<version>_x64__<publisher>\app\Claude.exe`.
   The setup script scans this directory and picks the newest version.

2. **Launch with `--user-data-dir`.** Despite being an MSIX-packaged app, the
   inner Electron runtime still respects command-line flags. Passing
   `--user-data-dir="C:\Users\<you>\AppData\Roaming\Claude-work"` (or any
   path you like) makes Electron use that directory for all per-user state.

3. **What lives in user-data-dir.** Things that are *per-instance*:
   - `Local Storage\leveldb\` — OAuth tokens, session state
   - `IndexedDB\` — chat history, drafts
   - `Cache\`, `Code Cache\`, `blob_storage\` — Chromium caches
   - Window position, zoom level, etc.

4. **What stays shared.** Things under `%USERPROFILE%\.claude\` (CLAUDE.md,
   MEMORY.md, plugins, skills, project settings) are **not** part of
   user-data-dir. They're shared across all instances, which is usually what
   you want — global config and the agent's memory travel with you, while
   sessions/auth are isolated.

5. **Why a self-healing launcher.** The desktop `.lnk` has to hardcode the
   exact Claude.exe path including its version number. When Claude updates,
   that path is gone. The launcher script in `%USERPROFILE%\.claude-dual-launcher\`
   re-scans `WindowsApps\Claude_*` at every run, so it always finds the
   current install regardless of version.

## FAQ

**Will this get my account banned?**
No — `--user-data-dir` is a public, supported Chromium/Electron flag, not a
hack against Anthropic's service. The only sessions-related risk is logging
in to the *same account* in multiple instances at the same time (don't do
that, as noted above).

**Does this duplicate Claude's disk usage?**
The Claude.exe binary itself is shared — only per-user state grows. Expect
~hundreds of MB per instance once you've accumulated chat history and caches.

**Can I use this with the regular Claude Code CLI (terminal-only)?**
This skill targets Claude *Desktop* specifically. The CLI handles auth
differently (via `~/.claude/.credentials.json`). If you only use the
terminal CLI, you don't need this skill.

**Does it work with Claude Desktop installed outside the Microsoft Store?**
Only the Microsoft Store / MSIX install is auto-detected in v1. If you have a
sideloaded build, you can still pass `--user-data-dir` manually — the
mechanism is the same, the path lookup is what differs.

## Roadmap

- [ ] macOS support (Claude.app + `LaunchAgent` / `open -n -a`)
- [ ] Linux support (AppImage / deb / Flatpak variants)
- [ ] List installed instances (`.\scripts\list.ps1`)
- [ ] Optional taskbar pinning helper

## License

MIT — see [LICENSE](./LICENSE).

## Contributing

PRs welcome. Especially for macOS/Linux support, additional instance-management
features, and bug reports from people with edge-case Windows installs.
