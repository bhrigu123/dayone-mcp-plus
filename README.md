# Day One MCP Plus

Read-only MCP access to your [Day One](https://dayoneapp.com) journals on macOS, **gated by Touch ID**, and working even when Day One's password lock is on.

Day One's official MCP server refuses to start while the app's password lock is enabled. That lock guards the app's UI; the journal itself lives in a local SQLite database. This tool reads that database directly, read-only, and puts its own lock in front of it: the first time an agent asks for journal data, you approve with Touch ID (or your Mac password). Access then stays open for a set window (30 minutes by default) and re-locks automatically, or immediately when your screen locks.

Not affiliated with or endorsed by Day One / Automattic.

## How it works

```
MCP client (Claude, etc.)
   │ stdio
   ▼
dayone-mcp-plus mcp      ← thin pipe, needs no permissions
   │ Unix socket (~/Library/Application Support/DayOneMCPPlus/agent.sock, owner-only)
   ▼
Day One MCP Plus.app     ← background helper; holds Full Disk Access + the Touch ID gate
   │ read-only SQLite
   ▼
~/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite
```

macOS attributes file access to the app that *launched* a process, so an MCP server started directly by your MCP client would need Full Disk Access granted to the client (and everything else it runs). Splitting it this way keeps that permission on this one small app.

## Install

Requires macOS 13+ and Day One for Mac.

Open **Day One MCP Plus**. Its setup window walks through three steps:

1. **Background helper**: turns on automatically (it appears under System Settings → General → Login Items).
2. **Full Disk Access**: click *Open Settings* and turn on Day One MCP Plus.
3. **Connect your AI app**: *Copy Agent Instructions* and paste them into your agent (Claude Code, Codex, …) to have it add the server, or copy the `claude mcp add` / `codex mcp add` command or JSON snippet yourself.

Open the app again any time to check status or remove the helper. If an agent tries to read before access is granted, the setup window opens by itself.

The unlock window defaults to 30 minutes: `defaults write com.bhrigu.dayone-mcp-plus unlockMinutes 60` changes it (takes effect when the helper restarts, e.g. `dayone-mcp-plus register`).

### From source

Requires Swift (Xcode or Command Line Tools).

```bash
scripts/install.sh      # builds, signs, installs to ~/Applications, turns on the helper, opens setup
scripts/uninstall.sh    # turns off the helper and removes everything
```

The app is signed with your first "Developer ID Application" or "Apple Development" certificate (override with `SIGN_IDENTITY=...`), which keeps its Full Disk Access grant across rebuilds. Without a certificate it falls back to ad-hoc signing, and you'll need to toggle Full Disk Access off and on after each rebuild.

The bundled executable also has a small CLI: `dayone-mcp-plus status | register | unregister | setup`.

## Releasing

`scripts/release.sh` builds a Developer ID–signed, notarized zip in `dist/` that others can install without Gatekeeper warnings. It needs a Developer ID Application certificate and notarization credentials; see the comments at the top of the script for the one-time setup.

## Tools

| Tool | What it does |
| --- | --- |
| `list_journals` | Journals with entry counts and first/last entry dates |
| `list_tags` | Tags with entry counts |
| `get_entries` | Entries filtered by journal, date range, tag, starred; paged |
| `search_entries` | Full-text search (all words must match) plus the same filters |
| `get_entry` | One entry's full text by id |
| `on_this_day` | Entries from a calendar day across all years |
| `access_status` | Whether access is unlocked and until when (never prompts) |
| `lock_journals` | Re-lock now |

Entries in the trash are excluded. Long entries are truncated to 4000 characters in list results (`max_chars` to change); `get_entry` always returns the full text.

## Caveats

- Day One's database schema is not a public API; an app update could change it. Everything here is read-only, so the worst case is a broken query, not a damaged journal.
- Anything an agent reads is sent to that agent's model provider.
- Logs: `~/Library/Application Support/DayOneMCPPlus/agent.log` (no journal content is logged).

## Development

```bash
swift build
tests/smoke.sh | python3 tests/summarize.py   # end-to-end MCP test against a fixture database
scripts/build-icon.sh                         # regenerate the icon after editing scripts/make-icon.swift
```
