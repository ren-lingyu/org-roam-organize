---
name: org-roam-organize-memory
description: Read Org-roam Organize's formal GAW memory when resuming project work or maintaining persistent project knowledge.
---

# Org-roam Organize memory

## Reading navigation

Locate the formal worktree with `git gaw status` and confirm its workspace in
`.gaw/config`. The following paths are relative to that worktree root; they
are workspace data, not bundled resources of an installed copy of this skill.

1. `memory/current.md`: current state, continuation and limitations.
2. `memory/design.md`: supported models, decisions and migration requirements.
3. `memory/validation.md`: evidence scope, validation limits and interpretation
   of reconstructed history.

For selected source evidence, consult `archive/` when relevant. For earlier
knowledge states, use `git gaw show` on formal first-parent history and follow
that snapshot's memory navigation.

## External tools and skills

- `git-agent-workflow`: GAW discovery, recovery, memory maintenance, history and
  checkpoints through the public `git gaw` interface.
- `git-maintenance`: staged-diff review and checkpoint message preparation.
