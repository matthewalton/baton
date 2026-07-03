---
name: next
description: Pick the next Baton ticket to work on, move it to In Progress, and start working it. Use when the user asks "what's next", "what should I work on", "pick something up", "grab a ticket", or a piece of work just finished and they're ready for the next one.
---

# Pick up the next ticket

Choose the most sensible next ticket, get the user's nod, then actually start the work — this skill ends with real work underway, not just a moved card.

## 1. Choose

- Call `get_board` with `cwd`.
- **Finish before starting**: if an in-progress-style column already has tickets, the top one is the default pick — resuming beats context-switching. Only pass over it if it's blocked (say so).
- Otherwise take the top of the committed column (usually Backlog), respecting position order — the board order is the user's prioritisation. Deviate only for a clearly higher `priority` ticket sitting lower, and say why.
- Ideas-column tickets are not candidates unless the rest of the board is empty; they haven't been committed to yet.

## 2. Confirm

- `get_ticket` for the full description and notes timeline.
- Present the pick in a couple of sentences: what it is, why it's next, and your rough plan of attack. One question if something is genuinely ambiguous; otherwise proceed on the user's go-ahead.

## 3. Start

- `move_ticket` to the in-progress column (top).
- `add_note` marking that work started and the intended approach.
- Begin the actual work in the repo.

## 4. While working

- Append `add_note` at meaningful checkpoints (approach changed, blocker hit, scope discovered) — notes are the ticket's memory across sessions.
- New ideas or follow-ups discovered mid-task: `search_tickets` first, then `create_ticket` into the first column rather than expanding scope.

## 5. Finish

When the work is done and verified: `move_ticket` to Done, and `add_note` with a short outcome summary (what shipped, anything intentionally left out).
