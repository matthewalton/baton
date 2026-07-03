---
name: capture
description: Capture an idea, follow-up, or bug onto the Baton board without derailing whatever is currently underway. Use when the user says "add this as an idea", "add this deferred idea", "ticket this", "defer this for later", "put that on the board", "don't lose this thought", or mentions something worth doing later mid-conversation.
---

# Capture

Get the thought onto the board in seconds and return to what was happening. This skill is deliberately lightweight: one write, one line of confirmation, no interrogation.

## 1. Shape the ticket

- Title: short and self-explanatory six months from now — not "fix the thing we discussed".
- Description: a sentence or two of context the title can't carry (where the idea came from, the file or symptom involved). Rough is fine — captured ideas haven't been committed to yet, so don't ask the user to spec it out.
- Only ask a question if you genuinely can't tell what the idea *is*; never ask about priority, sizing, or wording.

## 2. Check for duplicates

- `search_tickets` (with `cwd`) on the key terms first. It covers titles, descriptions, tags, and notes.
- If an existing ticket already covers it, `add_note` on that ticket with the new context instead of creating a twin, and say so.

## 3. File it

- `create_ticket` with `cwd`, into the **first column** (the ideas/inbox column) — captured thoughts land there, not in the committed backlog. Pass `project` only if the idea belongs to a different project than the one you're working in.
- Confirm in one line ("Filed 'Rate-limit the MCP server' as an idea") and pick the previous task straight back up. Don't summarise the board, don't suggest working the ticket now — the whole point was to defer it.
