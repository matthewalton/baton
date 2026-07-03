# MCP reference

Baton embeds an MCP server (streamable HTTP) at `http://127.0.0.1:8321/mcp`, live whenever the app is running. This page covers connecting agents other than Claude Code, and the full tool surface.

## Connecting other agents

Any MCP-capable agent connects with one config entry — no adapters, no extra processes:

| Agent | How to connect |
|---|---|
| **Codex CLI** | `codex mcp add baton --url http://127.0.0.1:8321/mcp` |
| **Copilot (VS Code)** | Add to `.vscode/mcp.json` or user `mcp.json`: `{"servers": {"baton": {"type": "http", "url": "http://127.0.0.1:8321/mcp"}}}` |
| **Cursor** | Add to `~/.cursor/mcp.json`: `{"mcpServers": {"baton": {"url": "http://127.0.0.1:8321/mcp"}}}` |
| **Gemini CLI** | Add to `~/.gemini/settings.json`: `{"mcpServers": {"baton": {"httpUrl": "http://127.0.0.1:8321/mcp"}}}` |
| **stdio-only clients** | Bridge with [`mcp-remote`](https://www.npmjs.com/package/mcp-remote): command `npx`, args `["mcp-remote", "http://127.0.0.1:8321/mcp"]` |

The server ships its usage conventions in the MCP `instructions` field (always pass `cwd`, search before filing, don't create projects unasked), so every client's model picks them up automatically — the Claude Code [skills](../skills/README.md) are a convenience layer, not a requirement.

## Tools

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

Project resolution for project-scoped tools: an explicit `project` name beats `cwd` matching, and an unmatched `cwd` returns an error listing known projects rather than filing anything silently.
