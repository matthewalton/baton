# Baton

Native SwiftUI macOS kanban app with an embedded MCP server (streamable HTTP, port 8321). SPM package, no Xcode project.

## Commands

- Build app bundle: `./scripts/build-app.sh` → `dist/Baton.app`
- Tests: `./scripts/test.sh` (plain `swift test` fails — Command Line Tools keep Testing.framework outside default search paths; the script adds the flags)
- Debug build: `swift build`

## Layout

- `Sources/BatonCore` — models, GRDB schema/migrations (`AppDatabase`), all data operations (`Repository`), MCP JSON-RPC + tools (`MCPHandler`), NIO HTTP server (`BatonServer`). UI-independent, fully tested.
- `Sources/BatonApp` — SwiftUI app. `AppStore` is the single ObservableObject; views never touch GRDB directly (they go through `store` / `store.repository`).
- Theming lives in `Theme.swift` (palettes, column tints, appearance override), driven by `@AppStorage` keys and exposed via the `\.batonTheme` environment; the picker is the app Settings window (⌘,). Priority badge colors stay fixed across themes.
- The app icon is generated at bundle time by `scripts/make-icon.swift` (called from `build-app.sh`); edit the script, not a PNG.
- Live UI refresh works via `Notification.Name.batonDataDidChange`, posted after every `Repository` write (MCP writes included — same process).
- The repo is also a Homebrew tap (`Formula/baton.rb`, head-only, runs `build-app.sh`) and a Claude Code plugin + marketplace (`.claude-plugin/` manifests, `skills/` → `/baton:capture|next|recap|triage`, model-invoked from natural language, `hooks/ensure-baton.sh` launches the app at session start, `.mcp.json` registers the server).

## Conventions

- Ticket ordering is a `position` Double; top = smallest. Insert between cards = midpoint, top = min − 1024, bottom = max + 1024.
- Column/project name matching is case-insensitive everywhere.
- Ticket deletes are soft (`deletedAt`); purge after 30 days happens on app launch.
- New schema changes = new numbered migration in `AppDatabase.migrator`; never edit `v1`.
- The MCP tool surface is defined in one place (`MCPHandler.registerTools`); update tests in `MCPHandlerTests` (tool count is asserted).
- Baton is a single-person tool: no team concepts (standups, assignees, sprints) in skills, tools, or docs. Skill `description` frontmatter is the auto-invocation trigger — write it around natural phrases a solo user would say, not slash-command names.
