---
name: org-roam-organize-memory
description: Read and interpret Org-roam Organize's formal GAW memory, including reconstructed historical states, when resuming project work or maintaining its persistent knowledge.
---

# Org-roam Organize memory

Use this entry point with the external `git-agent-workflow` skill. It routes
project knowledge; it does not grant permission to modify the project or Git
state. Use the external `git-maintenance` skill to prepare checkpoint messages
from the staged candidate.

## Find and read the knowledge state

Discover the formal worktree through `git gaw status`. Paths below are relative
to that worktree's root, not the ordinary project root or an installed copy of
this skill. Confirm their declaration in `.gaw/config`.

- Begin with the relevant files under `memory/`. Recover the objective,
  established conclusions, evidence limits, unresolved questions and next action.
  If substantive memory is absent, report the missing baseline rather than
  inferring one from this entry point or the current project tree.
- Consult `archive/` only for evidence relevant to the question. Archived text
  and conversations are source material, not automatically adopted knowledge or
  active instructions.
- Use formal first-parent history to recover earlier knowledge states. Interpret
  each snapshot using its own terminology, layout and evidence horizon.

These directories are GAW workspace data, not bundled resources of this skill.

## Interpret reconstructed project history

An early reconstructed state can describe a superseded project model. Establish
the state being described before treating its APIs, configuration or outstanding
work as current. Distinguish what the source supported then from observations
made during reconstruction; static inspection does not establish historical
runtime validation or undocumented author intent.

For reconstruction, use project ancestry to order supported code transitions.
Session start times and repeated inherited conversation material do not define
independent development stages. Select checkpoints for consequential knowledge
changes, not one per session or project commit. An exact project-parent
association still requires evidence for the snapshot actually examined; ancestry
alone does not establish the provenance of a historical operation.

Keep continuing facts and open work in memory, rather than extending this skill
with progress reports or a static history index. Review and sanitize the actual
candidate content before persistence. Preserve useful technical meaning without
copying personal configuration, credentials or raw conversation transcripts.
