# Org-roam Organize: early implementation baseline

## Scope and evidence

This is a retrospective reconstruction of the earliest implementation tracked
in this repository, not a description of present-day main or proof of when
project development began. The associated project snapshot supplies the
implementation and minimal README inspected for this state. That association
records this retrospective static review, not a historical execution or test
baseline. Checkpoints are created at reconstruction time.

The repository history before the supplied conversations is being recovered
from committed source and documentation. No contemporaneous conversations or
runtime results are available for this early interval. Reasons below describe
the observable consequences of the design; undocumented author intent remains
unknown.

## Project model

The package is an interactive organizational layer over Org-roam. MOC files
serve as navigable outlines of ID-linked file nodes. The central workflow
couples three representations of a note's classification: its file tags, its
physical location, and its position in a MOC outline. Moving a selected entry
is intended to update these together. Deletion likewise acts on both the entry
and its backing file, with directory removal inferred from movement settings.
This is a convention-driven workflow rather than a general ownership model
for arbitrary files and attachments.

Configuration supplies the organizing root, fixed MOC/fleeting/permanent
directories, movement policy and a manually maintained tag-to-MOC-ID mapping.
The top-level MOC is addressed by node ID. Most organizational actions are
guarded by a global minor mode; startup checks configuration and the working
directory. The mode supplies its own command bindings and installs configured
capture templates into Org-roam's global template collection.

Org-roam's database supplies membership and relationship queries. MOC updates
count tagged file nodes, write statistics into MOC properties, and append
missing members as ID-linked headlines. Literature backlink completion joins
external cite refs to citation records and appends missing citing-node links.
These operations materialize database-derived relationships into outlines;
they are not a full reconciliation of stale entries or a general citation
processor integration.

## Boundaries that matter for continuation

- The manual MOC mapping must agree with the actual note library. It is a
  configuration dependency, not an independently discovered catalog.
- Move/delete actions combine outline edits and filesystem changes. A configured
  ID directory is an operation-specific convention, not evidence that every
  existing note and attachment follows a universal bundle layout.
- Configuration checks do not establish transactional safety or successful
  runtime behavior. The tracked snapshot has no automated test suite or
  reproducible test definition; none was run during this reconstruction.
- Source commentary states broad organizational goals. It does not independently
  validate completeness, dependency compatibility or error recovery.

## Next reconstruction step

Inspect the later pre-conversation MOC changes as a separate durable state:
whether discovery and creation reduce the manually maintained mapping, and
which parts of the original workflow remain. Only then continue into the
supplied conversations. Preserve substantive design evolution without replaying
every typo fix or treating commit timestamps as the ordering authority.
