# Org-roam Organize: nil Inbox design adopted

## Current state and next action

The design for an explicit `:inbox nil` on non-MOC records is adopted;
implementation is pending. A read-only review confirmed the intended change
sites against the current project HEAD, whose worktree and index are clean:
the `org-roam-organize--record-inbox` accessor, the two `:inbox` checks in
`org-roam-organize--validate-registry` (declared value and resolved value),
and the MOC region Inbox lookup plus insertion planner. No source, test or
documentation edit has been made yet.

The next action is the implementation node: registry resolution and
validation, the nil insertion policy, ERT coverage, README,
defcustom/docstring and CHANGELOG updates, then full Nix verification. The
completed single-file MOC transition described below remains the implemented
baseline. Old user data migration is still manual and was not performed.
Future feature work, broader test migration and release preparation require
their own scope. Current contracts are in memory/design.md; evidence and
limits are in memory/validation.md; deferred testing work is in
memory/backlog.md.

## Motivation and completed stages

The former per-record MOC files coupled file lifecycle to entry reconciliation.
The first stage separated parsing, planning, existing-entry application and
position-based insertion while retaining the file-level compatibility wrapper
for Cite. Insertion markers must advance at replacement boundaries. Basic records
may share directories; safe paths, names and tags retain their own constraints.

The second stage changed registry validation, file capture/discovery, region
creation, synchronization, tests and migration documentation together. It is
one coherent feature commit with a breaking configuration/layout contract, not
a partially switched intermediate model. Ordinary capture and Cite production
behavior remain outside the functional change.

The earlier MOC template-source fix is incorporated: MOC file heads use the
unique MOC record's template. The newer model now has only that one file.

## Adopted nil Inbox design (implementation pending)

The single-file MOC model reconciles entries across the whole management
subtree, but missing members currently require a named direct-child Inbox.
Some layouts should support unclassified entries directly in the management
headline's own section. The adopted extension lets non-MOC records explicitly
declare `:inbox nil`.

- Omission still resolves to the default "Inbox"; a string retains the
  existing named-Inbox policy. Only an explicit nil selects the management
  headline's own initial section as the insertion target.
- Scope boundary: the unique MOC record must still use a string Inbox name.
  Management headline creation and its level-1 Inbox policy are unchanged;
  `org-roam-organize--moc-create-regions` gets no nil branch.
- Architectural invariant: Inbox configuration determines only the insertion
  location of missing members, never the membership or reconciliation scope.
  Reconciliation still spans the entire management subtree, and existing
  entries are never migrated when the policy changes. Under nil, existing
  Inbox headlines are ordinary user content: not located, created, removed or
  checked for duplicates.
- Implementation direction: distinguish absent from explicit nil via
  `plist-member` in the accessor; reject only illegal values in the validator
  (both the declared-value and resolved-value checks, ideally one shared
  predicate); bypass the named-Inbox lookup for nil; reuse the existing
  AST-based `org-roam-organize--first-child-headline-begin` boundary and the
  retained-marker insertion planning with the management headline as target.
- Current state: design adopted; implementation and verification are pending.

## Final MOC decisions

- Exactly one basic MOC record identifies one tagged level-0 file; it has no
  management region or own member index.
- Optional :moc-id and :moc-path are independent simultaneous constraints.
  Tag discovery is always unique at level 0, with join rows deduplicated by ID.
  The default path is a creation target only; undeclared paths may change within
  the safe root. Conflicts never fall back to another identity query.
- Each non-MOC record has one CUSTOM_ID=:tag region with its declared/derived
  title. Title mismatches are errors, not automatic renames. All regions share
  a level, defaulting to 1, but may have different parents.
- All tags use the nonempty Org alphabet of letters/digits and _@#%.
  Management titles must parse back identically as plain single-line Org
  headlines, including effective target TODO syntax. File titles need only
  satisfy their own single-line constraint.
- For missing regions, L1 appends at EOF. Every L>1 uses the MOC record's
  level-1 :inbox, inserting before its first child or at its subtree end.
  If absent, create only that level-1 Inbox at EOF. Keep common L and never
  invent intermediate levels. Duplicate active level-1 Inboxes reject preflight.
- Each present region allows at most one active matching direct-child member
  Inbox at L+1. Sync checks even empty/complete rosters before all edits.
  Deeper names and other regions are independent. Create an absent member Inbox
  only when missing members need insertion. First-child/subtree-end placement
  preserves properties, planning metadata and handwritten text.
  Once implemented, records declaring `:inbox nil` skip this lookup and its
  duplicate preflight entirely; see the adopted design section above.
- Missing-region same-title headlines with unknown/empty CUSTOM_ID outside
  known managed subtrees are suspicious and reject preflight. Title alone
  cannot establish identity; plain no-CUSTOM_ID manual headings and valid
  distinct tagged identities remain legal.
- Capture preserves literal MOC file title, structural titles/CUSTOM_ID and
  FILETAGS through pre-finalize insertion/restoration. Other template fields
  retain native expansion. Preset IDs use the minimal compatible capture
  extension and success depends on finalization.
- Sync uses one MOC planning AST, per-region plans, globally descending edits
  and advancing markers cleaned with unwind-protect. Only changed buffers
  receive one effective save and DB refresh. Entry-value parsing and DB refresh
  still have their own parses.
- Membership is tagged level-0 nodes outside the MOC file. Preserve per-region
  ordering, :delete t, duplicates and malformed diagnostics, COMMENT/source
  exclusion and manual subsections. A node may occur in several tag regions.
  Missing regions are reported; sync does not perform create.

## Verification and remaining migration

All 45 inputs of the committed MOC implementation match the final isolated
passing copy byte-for-byte. Full x86_64-linux flake checks passed package build
with warnings as errors, package-lint, treefmt and 200 ERT tests: core 131,
Citar 48, display 13, export 8. The current documentation commit changes README
only; all other 44 inputs still match. Its complete diff was statically reviewed
against the implementation, and committed whitespace checks pass. The user then
ran nix flake check on the clean committed project: exit 0, all checks passed
from cache, with the same four ERT derivations as the actual 200-test run.
This validates current check inputs without claiming fresh test execution.
The agent did not rerun checks or formatting for this documentation follow-up.

The reproducible 10,000-entry/four-region test observed 4.314s for first sync
(save/DB 1/1), and 2.503s unchanged (0/0). This is evidence, not a timing threshold
or node cap. Tests use real save/DB operations with controlled membership queries.
Other platforms, minimum-version full runtime and interactive GUI usage are not
certified. Temporary reports are conveniences, not required memory dependencies.

Users must remove non-MOC :moc-id/:moc-path declarations, include the MOC tag in
its template filetags, select/preserve one file ID, migrate members and manual
content into declared CUSTOM_ID regions, and resolve extra old map tags before
refreshing the DB. Preserve or convert incoming links to old per-record file IDs;
CUSTOM_ID does not replace an Org-roam ID. Old managed properties and files are
not automatically deleted or merged.

## Existing boundaries

v0.8.0 remains TODO with no publication or release-state transition implied.
Its detailed release manuscript remains unfinished. Historical release notes,
CLOSED timestamps and dependency declarations are unchanged by this work.
Ordinary project commits and release operations remain user-owned.

The broader Cabal-style/project-owned test-runner and package checkPhase migration
remains deferred. Current separate Nix/Guile ERT suites stay in place. The earlier
bounded cite export suite replacement does not reopen that backlog.

The existing unified citation/export/display/Citar architecture remains supported
as described in design.md. Native oc-basic needs the same resolved bibliography
available through discovery and export info; keep dynamic export context and
processor-independent ownership. Display title caches require explicit refresh.
Historical native Org 9.5.2 evidence is not full package support on Emacs 28.

Repository-facing history uses concise root CHANGELOG.org entries and independent
CHANGELOGS/<tag>.org release manuscripts without backlinks to the root. Preserve
native Org syntax, relative links, source escaping and user-owned release states.
Org docs and .gitignore remain in treefmt scope; LICENSE and flake.lock are the
explicit project exclusions.
