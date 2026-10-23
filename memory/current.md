# Org-roam Organize: pre-conversation baseline

## Scope and evidence

This is a retrospective reconstruction of the last committed project state
before the earliest supplied development conversation, not a description of
present-day main. The associated project snapshot supplies the implementation
and README inspected for this state. The association records this retrospective
static review, not a historical execution or test baseline. Checkpoints are
created at reconstruction time.

The tracked early interval has been reviewed from repository initialization
through this baseline. Its two consequential states are the initial
convention-driven organization model and the subsequent metadata-driven MOC
model. Configuration-check repairs, spelling, formatting, licensing and README
changes were considered as context; they do not require separate knowledge
checkpoints. The first-parent memory history preserves the initial model.

No contemporaneous conversations or runtime results are available for this
early interval. Static code and documentation establish the model and its
changes, not undocumented author intent or successful interactive use.

## Organizing model

The package provides a global minor mode for organizing Org-roam file nodes
through MOC outlines, tags and a fixed directory scheme. Its original workflow
still couples a node's classification, physical location and ID-linked MOC
headline. Movement changes these representations together; deletion operates
on a selected entry and its backing file, with directory cleanup inferred from
movement policy. Fleeting/permanent directories and source/target tags remain
part of this model. Their presence does not establish a universal ownership
rule for every note and attachment.

The important change is that MOCs now describe which tag they manage in their
own node properties. The database can discover the tag-to-MOC-ID catalog from
MOC-tagged file nodes rather than requiring the user to maintain those IDs in
a separate mapping. Configuration instead declares tag/title pairs and a
capture template for creating MOC nodes. This reduces duplicated node-identity
configuration, but makes correct MOC tags, properties and database indexing
part of the operational contract. The top-level MOC is opened by configured
file path rather than node ID.

MOC updates count tagged file nodes, write a configurable count property, and
append missing members as ID-linked headlines. Literature backlink completion
uses external cite refs and citation records to append missing citing-node
headlines. Both are database-derived outline maintenance; existing stale
entries are not comprehensively reconciled. The relationship to file nodes,
rather than arbitrary headlines, matters when interpreting counts and links.

Most organizational actions require the mode. Configuration checks and a
working-directory condition gate startup. The package supplies default command
bindings, and mode setup installs its MOC capture template into Org-roam's
global collection. Dependencies are declared through source-level requires
and explanatory text; this snapshot predates standard package header metadata.

## Historical limitations and validation

- Dynamic MOC discovery is visible in source, but the movement consumer has a
  static inconsistency: the catalog returns node IDs, while target selection
  applies a list operation to the ID and then uses the result as a file path.
  This prevents treating the advertised dynamic movement path as verified.
  The finding belongs to this historical snapshot, not a request to repair
  today's implementation.
- Move/delete still infer filesystem effects from legacy movement settings.
  Configuration validation alone does not prove attachment ownership,
  transactional updates or recovery after a partial failure.
- The README's safety and completeness claims are descriptive claims, not
  independent validation evidence. The tracked baseline has no automated test
  suite or reproducible test definition. No historical snapshot was executed
  or tested during this reconstruction.

## Next reconstruction step

The early repository baseline is established. Continue with the supplied
package-standardization conversation
`019f45a2-cfd1-7fe1-8332-f877cbc91b4a`, then the supported subsequent development
stages. Those conversations and the ordinary project's `gaw-input/` reference
materials are external reconstruction inputs, not bundled GAW evidence or
instructions. Distinguish their historical test reports from this static review,
reconcile superseded conclusions as the knowledge state advances, and leave
the eventual final memory describing the current project. Reconstructing the
later conversation horizon remains pending.
