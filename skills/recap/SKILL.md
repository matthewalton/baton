---
name: recap
description: Read-only recap of recent Baton board activity — what got finished, what's in flight, what's next, what looks stuck. Use when the user asks "where was I", "where did I leave off", "catch me up", "what's the state of the board", "what did I get done this week", or returns to a project after time away.
---

# Recap

Give the user a fast, honest picture of where their project stands. **Strictly read-only** — no writes, no matter what you notice; at most, end with one suggestion (e.g. "want me to tidy the board?").

## Gather

- `get_board` with `cwd`. If the user asks about everything they're working on, use `list_projects` and repeat per project.
- Recency lives in the notes timeline: call `get_ticket` on tickets in active columns (and recent-looking Done tickets) to read timestamps and authors. Default window is the last 7 days unless the user says otherwise.

## Report

Keep it to a screenful, in this order:

1. **Done** — tickets completed in the window, one line each.
2. **In flight** — what's in progress and the latest note per ticket. Note authors distinguish the user's own updates from agent updates — useful for "did I do that or did Claude?".
3. **Up next** — the top 2–3 of the committed column.
4. **Flags** — anything stuck (in progress but silent all window), or a growing pile in one column. Skip the section if there's nothing; don't invent concerns.

Plain prose or short bullets — this is a briefing, not a dashboard. Lead with the single most important fact (e.g. "you shipped 3 things, one ticket's been stuck since Tuesday").
