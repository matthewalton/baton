# Deck

Native SwiftUI macOS kanban app with an embedded MCP server (streamable HTTP, port 8321). SPM package, no Xcode project.

## Commands

- Build app bundle: `./scripts/build-app.sh` → `dist/Deck.app`
- Tests: `./scripts/test.sh` (plain `swift test` fails — Command Line Tools keep Testing.framework outside default search paths; the script adds the flags)
- Debug build: `swift build`

## Layout

- `Sources/DeckCore` — models, GRDB schema/migrations (`AppDatabase`), all data operations (`Repository`), MCP JSON-RPC + tools (`MCPHandler`), NIO HTTP server (`DeckServer`). UI-independent, fully tested.
- `Sources/DeckApp` — SwiftUI app. `AppStore` is the single ObservableObject; views never touch GRDB directly (they go through `store` / `store.repository`).
- Live UI refresh works via `Notification.Name.deckDataDidChange`, posted after every `Repository` write (MCP writes included — same process).

## Conventions

- Ticket ordering is a `position` Double; top = smallest. Insert between cards = midpoint, top = min − 1024, bottom = max + 1024.
- Column/project name matching is case-insensitive everywhere.
- Ticket deletes are soft (`deletedAt`); purge after 30 days happens on app launch.
- New schema changes = new numbered migration in `AppDatabase.migrator`; never edit `v1`.
- The MCP tool surface is defined in one place (`MCPHandler.registerTools`); update tests in `MCPHandlerTests` (tool count is asserted).
