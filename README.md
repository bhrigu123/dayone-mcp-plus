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
Day One MCP Plus.app      ← launchd agent; holds Full Disk Access + the Touch ID gate
   │ read-only SQLite
   ▼
~/Library/Group Containers/5U8NS4GX82.dayoneapp2/Data/Documents/DayOne.sqlite
```

macOS attributes file access to the app that *launched* a process, so an MCP server started directly by your MCP client would need Full Disk Access granted to the client (and everything else it runs). Splitting it this way keeps that permission on this one small app.

## Install

Requires macOS 13+, Swift (Xcode or Command Line Tools), and Day One for Mac.

```bash
scripts/install.sh                     # or: scripts/install.sh --unlock-minutes 60
```

Then:

1. Give **Day One MCP Plus** Full Disk Access. Until it has it, the app shows a dialog (at launch, and whenever an agent tries to read) with a button to the right Settings pane. Turn it on and choose "Quit & Reopen", or restart it with `launchctl kickstart -k gui/$(id -u)/local.dayone-mcp-plus.agent`.
2. Add it to your MCP client, e.g. `claude mcp add dayone -s user -- ~/Applications/Day\ One\ MCP\ Plus.app/Contents/MacOS/dayone-mcp-plus mcp`

The app is ad-hoc signed, so every rebuild changes its signature and macOS drops the Full Disk Access grant; toggle it off and on after reinstalling a new build.

Uninstall with `scripts/uninstall.sh`.

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
