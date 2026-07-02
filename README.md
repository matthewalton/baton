# Deck

A personal kanban board for macOS, built to pair with Claude Code (or any MCP-capable agent). Agents defer ideas onto your board, add progress notes to tickets, and move them between columns — you manage the board in a native SwiftUI app.

## How it works

Deck is a single native app that embeds a localhost HTTP server. The server speaks MCP (streamable HTTP) directly at `http://127.0.0.1:8321/mcp`, so there is no proxy process and no per-repo setup. Data lives in SQLite at `~/Library/Application Support/Deck/deck.sqlite`.

- **Projects** are fully separate boards. Each registers one or more folder paths; when an agent passes its working directory, Deck matches it to the right project automatically (longest path prefix wins).
- **Boards** start with Ideas / Backlog / In Progress / Done, but columns can be renamed, added, removed, and reordered per project — from the UI or by the agent.
- **Tickets** have a title, markdown description, priority, tags, and an append-only notes timeline. Notes are marked by author (you vs. agent).
- **Deletes are soft**: trashed tickets are restorable for 30 days, then purged.
- The MCP endpoint only works while the app is running.

## Build

Requires macOS 14+ and the Swift 6 toolchain (Command Line Tools are enough; full Xcode not required).

```sh
./scripts/build-app.sh     # builds dist/Deck.app (ad-hoc signed)
./scripts/test.sh          # runs the test suite
```

Move `dist/Deck.app` to `/Applications` if you like, or run it in place.

## Connect Claude Code

```sh
claude mcp add --transport http --scope user deck http://127.0.0.1:8321/mcp
```

`--scope user` makes it available in every repo. Claude discovers the tools automatically; the server's instructions tell it to always pass its working directory so tickets land in the right project.

## MCP tools

| Tool | Purpose |
|---|---|
| `list_projects` | Projects with paths, columns, ticket counts |
| `create_project` | New project (+ registered folder, custom columns) |
| `get_board` | Columns and tickets for a project |
| `create_ticket` | File an idea/bug/follow-up (lands top of first column) |
| `get_ticket` | Full detail including notes timeline |
| `update_ticket` | Change title/description/priority/tags |
| `move_ticket` | Move between columns (top or bottom) |
| `add_note` | Append a timestamped note |
| `delete_ticket` / `restore_ticket` | Trash and restore |
| `search_tickets` | Substring search across titles, descriptions, tags, notes |
| `add_column` / `rename_column` / `delete_column` / `reorder_columns` | Board management |

Project resolution for project-scoped tools: explicit `project` name beats `cwd` matching; an unmatched `cwd` returns an error listing known projects rather than filing anything silently.

## Not in v1 (deliberately)

Menu-bar residency / start-at-login, auth on the endpoint, archive view, cross-project inbox, and sync. All addable without schema changes.
