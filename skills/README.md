# Baton skills

Workflow skills bundled with the Baton Claude Code plugin. Installing the plugin (`/plugin install baton@baton`) adds all four; each is a thin, opinionated layer over the MCP tools — the tools work fine without them.

You don't need to type the slash commands: Claude invokes these itself when your request matches. Say "add this as an idea", "what should I work on", "where was I", or "clean up the board" and the right skill kicks in. The `/baton:*` forms exist if you want to be explicit.

| Skill | Say something like | What it does |
|---|---|---|
| [`/baton:capture`](capture/SKILL.md) | "add this as an idea", "ticket this for later" | File a thought into the ideas column and get back to work |
| [`/baton:next`](next/SKILL.md) | "what's next", "what should I work on" | Pick the next ticket, move it to In Progress, and start working it |
| [`/baton:recap`](recap/SKILL.md) | "where was I", "catch me up" | Read-only recap: what finished, what's in flight, what's stuck |
| [`/baton:triage`](triage/SKILL.md) | "clean up the board" | Groom the board — stale tickets, duplicates, Done pile-up (propose, then apply) |

## `/baton:capture`

Deliberately lightweight: shape a title, check for duplicates via `search_tickets`, file into the first (ideas) column, confirm in one line, and return to whatever was underway. Never interrogates you about priority or wording — captured ideas are allowed to be rough.

## `/baton:next`

Ends with real work underway, not just a moved card. Prefers finishing what's already in progress over starting fresh, otherwise takes the top of the committed column (board order is your prioritisation). Confirms the pick with you, moves the ticket, notes the approach, and keeps appending notes at meaningful checkpoints while working.

## `/baton:recap`

Strictly read-only briefing for coming back to a project: what shipped in the window (default 7 days), what's in flight and its latest note, what's up next, and anything that looks stuck. At most it ends with a suggestion — usually "want me to tidy the board?".

## `/baton:triage`

Propose-then-apply board grooming — it never mutates the board before you've agreed to the batch. Hunts for stuck in-progress tickets, duplicates (verified via `search_tickets`), unactionable tickets in committed columns, and a bloated Done column.
