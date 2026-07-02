<div align="center">

<img src="assets/icon.png" width="140" alt="Baton app icon">

# Baton

**A personal kanban board for macOS, built for you *and* your agent.**

You drag the cards. Claude files the ideas. Work passes between you like a baton.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![MCP](https://img.shields.io/badge/MCP-streamable%20HTTP-6875E4)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)

<img src="assets/board-dark.png" width="920" alt="Baton board in dark mode — four tinted kanban columns with tickets">

</div>

---

Baton is a native SwiftUI kanban app with an MCP server built in. While you work with Claude Code (or any MCP-capable agent), ideas, bugs, and follow-ups inevitably come up mid-task — instead of losing them, your agent defers them straight onto your board, adds progress notes as work happens, and moves tickets between columns. You review, prioritise, and manage everything in a fast native app.

No Electron, no cloud, no account. One app, one SQLite file, one localhost port.

## ✨ How it works

Baton embeds a localhost HTTP server that speaks MCP (streamable HTTP) directly at `http://127.0.0.1:8321/mcp` — no proxy process, no per-repo setup. Data lives in SQLite at `~/Library/Application Support/Baton/baton.sqlite`.

- 🗂 **Projects are separate boards.** Each project registers one or more folder paths; when an agent passes its working directory, Baton resolves the right project automatically (longest path prefix wins).
- 📌 **Columns are yours to shape.** Boards start with *Ideas / Backlog / In Progress / Done*, but columns can be renamed, added, removed, and reordered per project — from the UI or by the agent.
- 🎫 **Tickets carry real context.** Title, markdown description, priority, tags, and an append-only notes timeline — with each note marked by author, so you can tell your thoughts from your agent's.
- 🗑 **Deletes are soft.** Trashed tickets are restorable for 30 days, then purged.
- 🔄 **Live everywhere.** MCP writes land in the running UI instantly — file a ticket from a Claude session and watch it appear at the top of the board:

<div align="center">
<img src="assets/live-updates.gif" width="880" alt="Claude creates a ticket over MCP and it appears on the board instantly, then a ticket moves to Done">
<br>
<sub>Claude files an idea mid-session, then moves a finished ticket to Done — no refresh, no polling.</sub>
</div>

> The MCP endpoint is only live while the app is running — Baton *is* the server.

## 🚀 Getting started

Requires macOS 14+ and the Swift 6 toolchain (Command Line Tools are enough; full Xcode not required).

```sh
git clone <this repo> && cd baton
./scripts/build-app.sh     # builds dist/Baton.app (ad-hoc signed)
open dist/Baton.app
```

Move `dist/Baton.app` to `/Applications` if you like, or run it in place. Tests run with `./scripts/test.sh`.

### Connect Claude Code

```sh
claude mcp add --transport http --scope user baton http://127.0.0.1:8321/mcp
```

`--scope user` makes Baton available in every repo. Claude discovers the tools automatically; the server's instructions tell it to always pass its working directory so tickets land in the right project. Then, mid-session:

> *"Good idea, but out of scope — I'll put it on the board."* 🎉

## 🎨 Themes

Baton ships three hand-tuned palettes, each with matching light and dark variants. Pick yours in **Settings (⌘,)**, along with a light/dark override and a toggle for tinted columns (soft per-column hue washes that cycle across the board — shown in the hero shot above).

| Graphite & Iris | Paper & Pine | Harbor |
|:---:|:---:|:---:|
| ![Graphite & Iris, light](assets/theme-graphite-light.png) | ![Paper & Pine, light](assets/theme-pine-light.png) | ![Harbor, dark](assets/theme-harbor-dark.png) |
| Cool neutrals, indigo accent — the default | Warm paper tones, forest green accent | Sea-glass blues, teal accent |

Priority badge colors stay fixed across themes, so urgent always reads as urgent. Even the app icon is code — rendered at build time by [`scripts/make-icon.swift`](scripts/make-icon.swift).

## 🛠 MCP tools

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

## 🏗 Architecture

```
Sources/
├── BatonCore/    UI-independent, fully tested
│   ├── Models + GRDB schema & migrations (AppDatabase)
│   ├── All data operations (Repository)
│   ├── MCP JSON-RPC + tool definitions (MCPHandler)
│   └── SwiftNIO HTTP server (BatonServer)
└── BatonApp/     SwiftUI app
    ├── Single ObservableObject store (AppStore)
    ├── Board, ticket detail, sheets, drag & drop
    └── Theming (Theme.swift)
```

Plain SPM package — no Xcode project. The app and the MCP server share one process and one `Repository`, so every write (agent or human) refreshes the UI through a single notification.

## 🔭 Not in v1 (deliberately)

Menu-bar residency / start-at-login, auth on the endpoint, archive view, cross-project inbox, and sync. All addable without schema changes.
