---
name: triage
description: Groom the current project's Baton board — surface stale tickets, duplicates, missing priorities, and a bloated Done column, then apply agreed clean-ups. Use when the user says "clean up the board", "the board is a mess", "tidy my tickets", "triage", or complains that the board has gotten stale or cluttered.
---

# Board triage

Walk the current project's board with the user and leave it tidier than you found it. This is a **propose-then-apply** workflow: never mutate the board before the user has agreed to the batch.

## 1. Read the board

- Call `get_board`, passing `cwd` so Baton resolves the project from the working directory. Only pass `project` if the user names a different one.
- For tickets that look stale or ambiguous, pull detail with `get_ticket` — the notes timeline (authors + timestamps) tells you when anything last happened.

## 2. Diagnose

Look for, in priority order:

1. **Stuck work** — tickets in an in-progress-style column with no notes or movement for over a week. These are the most expensive: they silently block the "one thing at a time" signal the column is meant to give.
2. **Duplicates / overlaps** — before flagging, confirm with `search_tickets` (it covers titles, descriptions, tags, and notes).
3. **Unactionable tickets** — no description, vague title, or missing priority where the column implies commitment (backlog and beyond). Ideas-column tickets are allowed to be rough; don't over-groom them.
4. **Done pile-up** — a long Done column is noise. Deletes are soft (30-day restore), so proposing deletion of old Done tickets is low-risk.
5. **Ordering** — top of each column should be the next thing worth doing. Flag obvious inversions (e.g. an urgent ticket buried under low-priority ones).

## 3. Propose

Present one concise triage report: each finding, why it matters, and the exact action you propose (move / update / merge-and-delete / delete). Group by action type so the user can approve whole groups at once. Ask which to apply.

## 4. Apply

For approved actions only:

- `move_ticket`, `update_ticket`, `delete_ticket` as agreed.
- When merging duplicates: copy anything unique (description points, notes worth keeping) onto the survivor via `update_ticket`/`add_note` **before** deleting the other.
- Add a brief `add_note` on tickets whose state you changed materially (e.g. "moved back to Backlog — no activity since <date>"), so the timeline explains itself later.

Finish with a one-line summary of what changed.
