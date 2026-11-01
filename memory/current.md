# Org-roam Organize: Cite export committed and validated

## Current state and continuation

The user committed the complete approved cite implementation. Read-only review
confirmed a clean project worktree/index and all 45 committed inputs matching
the isolated validated copy, with obsolete repair files absent. The planning
GAW checkpoint preceded implementation; the user first committed only NEXT -> TODO
for v0.8.0. Keep that release state,
historical releases, dates, dependency declarations and lockfile unchanged.

The committed implementation provides scoped UUID/citekey/bibliography conversion, preserves
interactive full-library discovery and :bibliography opt-in, removes the bundled
BibLaTeX repair layer, and replaces its suite/check with ert-cite-export. README,
docstrings and only the v0.8.0 changelog content describe the final architecture.

Real oc-basic exports established that info-only propagation is insufficient:
this processor queries org-cite-list-bibliography-files for entries. The common
advice now exposes the same resolved per-export list through discovery. Before
transformation native discovery is preserved; afterwards only that export's
resolved list is exposed. Dynamic bindings restore interactive discovery on
success/error. Do not add processor-specific code. See memory/design.md.

The final filtered copy under ignored tmp/cite-validation/project passed
nix flake check --no-write-lock-file on x86_64-linux, including package build,
package-lint, treefmt and all 159 ERT tests (core 90, Citar 48, display 13, export 8).
Byte comparisons confirmed all 45 selected project inputs match the validated
copy. The subsequent committed tree matches that same copy, and commit whitespace
checking passes. See validation.md for version evidence and limits. The project
parent of this confirmation checkpoint identifies the exact inspected commit;
no tests were rerun merely to establish that association.

The user requires isolated flake validation, superseding earlier system-Emacs
and direct-download proposals. tmp/cite-validation/minimum passed native standard
input and info propagation on current Emacs 31.1/Org 9.8.7 and historical nixpkgs
22.05 Emacs 28.1/Org 9.5.2. The latter is native Org evidence, not full package
support on Emacs 28. Earlier exact Org 9.5 source checks were also Nix-isolated.
The user limited historical-version research; no further search is needed.

The cite implementation task is complete, including source, regression coverage,
documentation and manual project commit. No implementation or staging work remains.
Future release preparation is separate: v0.8.0 stays TODO, its detailed release
manuscript remains unfinished, and no release tag/publication is implied. Ordinary
project commits and release-state transitions remain manual. Preserve the existing
validation limits rather than rerunning or expanding checks without a new reason.

The broader testing migration remains deferred in memory/backlog.md. This bounded
suite replacement does not reopen package checkPhase migration, new runners or
general test reorganization. Task-owned validation artifacts remain under ignored
tmp. Isolated checks use 120s timeouts and no lock writes; no system packages or
project dependencies were changed.

Both root inputs, nixpkgs and personal-nixpkgs, moved to newer revisions. Their
original source specifications and the full lock graph are unchanged; personal-nixpkgs
still follows root nixpkgs. No transitive lock node changed. The root flake manifest
changed only its explicit treefmt exclusion list.

README.org, CHANGELOG.org, CHANGELOGS/*.org and .gitignore are now included in the
configured treefmt scope. Only LICENSE and flake.lock remain explicitly excluded by
the project; flakeCheck stays enabled. This supersedes the former Org/gitignore
exclusions. Formatter selection comes from the framework; the later cite candidate passed
the resulting complete treefmt check. Do not reintroduce the old exclusions from historical memory.

CHANGELOG.org now contains seven DONE historical versions (v0.1.0-v0.7.0) with
matching tag CUSTOM_ID values, UTC CLOSED records and local detailed-note links.
The user manually set these historical states and has since changed the development
entry from NEXT v0.8.0 to TODO v0.8.0 while considering an expanded testing scope.
CUSTOM_ID v0.8.0 remains. That entry has no CLOSED or release-date claim. Deferring
the migration does not authorize reverting TODO to NEXT; lifecycle state is the
user's decision. The historical state-assignment task remains complete.

No CHANGELOGS/v0.8.0.org was requested or created in this historical migration.
Completing and reviewing that detailed manuscript is still a prerequisite for a
future 0.8.0 release under the adopted profile. No local v0.8.0 tag exists in the
inspected repository. Do not infer publication or permission to transition NEXT
from committed version metadata, successful earlier tests or completed history.

## Adopted document and formatting policy

Root CHANGELOG.org keeps concise categorized user-visible history and actionable
Breaking migration directions. Complete historical Release Notes live in
CHANGELOGS/<tag>.org. Plain version titles, matching CUSTOM_ID properties and local
links replace hosting-platform URLs as version identity. Historical migration
instructions are in local detailed files. The user has now explicitly removed
all detail-to-root backlinks, superseding the earlier temporary decision to retain
them. Each detailed Release Notes file is an independently understandable authoritative
manuscript. Root-to-detail links remain. Future tag extraction/conversion must not
need a backlink rewriting/removal rule or a root summary with a matching structure.
Historical detail recovery from a successor tag likewise does not require that
snapshot's root changelog to contain a corresponding summary entry.

Use English and native Org syntax, omit empty categories and internal-only work,
and preserve meaningful category ordering. Headline-to-first-object spacing has
no blank line, all Org keyword names and source block delimiters are lowercase,
trailing spaces are
removed, and tables are aligned with org-table-align. Preserve Org source-block
escaping and the user's formatting edits. File links must be repository-relative;
a machine-specific v0.1.0 backlink was corrected before the user staged/committed it.

Root declares TODO NEXT WAIT | DONE CANCELED, logdone and TIMEZONE UTC. The user
explicitly requested agent-written CLOSED records for the existing historical
entries, overriding that skill restriction for this migration. Those records use
the peeled tag commit's committer epoch, converted to UTC at minute precision;
they are not platform publication timestamps. Existing state transitions remain
human-owned, and this time-write exception does not authorize future changes.

## Evidence and source corrections

Released source trees and historical READMEs govern substantive claims; old hosted
notes provide supplementary wording, examples and context. Seven published note
bodies were re-read through the GitHub connector and matched the earlier review.
Endpoint comparisons, package requirements and historical registry examples support
the entries. Source identifiers were verified against their version/predecessor.

The v0.4.0 hosted notes incorrectly named the former command
org-roam-organize-moc-update; actual source defines org-roam-organize-update-mocs.
The new detailed notes use the actual interface. Brief v0.2.0 notes were supplemented
with the declared Emacs minimum increase and default-keymap removal. The latest
skill permits verified initial-release capabilities to be described for v0.1.0
without a predecessor. ref.org is recommended literature configuration; ordinary
node paths default to ${slug}.org.

The final 0.8.0 root summary now explicitly records both Nix check renames:
ert-citar -> ert-cite-citar and ert-biblatex -> ert-cite-export. README and current
check overlays agree. User-facing history must not narrate release-note mistakes
or historical research; keep discrepancies in reports/memory. Hosted notes and
historical tagged trees were not rewritten.

## Tracking and verification

The .gitignore whitelist still uses !/CHANGELOGS/*.org. It now groups root-file
exceptions before directory groups and places *~ last. Its nonempty pattern inventory
is unchanged. The nine Org documents changed only keyword case, whitespace and Org
source escaping; documented version states, times, interfaces and release contents
are unchanged. Additional comma escaping protects ROAM_NODE/ROAM_CITING_NODE examples.

Read-only verification checked all lock nodes, original root source definitions,
follows relationships, all nine Org diffs and the gitignore pattern inventory.
All three commits pass Git whitespace checks and the documentation remains trackable.
That earlier review ran no runtime checks. The later cite candidate now passes
full isolated flake validation with the refreshed inputs and formatting scope;
earlier installed-package smoke results still describe their original snapshot.

Earlier history-migration static verification covered eight files, 18 local links, seven UTC CLOSED records,
25 source blocks, heading spacing, matching/unique per-file IDs, lowercase block
delimiters, 50 historical project identifiers, ignore coverage and staged/worktree
whitespace checks. Earlier no-index whitespace checks on new nonempty files accepted
expected status 1 only without diagnostics. emacs -Q --batch ran org-table-align on
two tables and removed 26 headline-adjacent blank lines; formatting-only comparisons
preserved other content. Eight Emacs Lisp example blocks had balanced strings and
parentheses but were not evaluated. No full Org export/render or current Nix/runtime
validation was performed for this documentation work.

Earlier 0.8.0 package checks and installation smoke validation remain separate
recorded evidence on x86_64-linux with default Emacs 31.1; they do not establish
minimum-version, other-system or straight runtime compatibility. See
memory/validation.md. Actual release operations and publication remain separate.

## Testing discussion and final decision

The user considered moving core/BibLaTeX/display ERT and package-lint into the
package checkPhase, retaining optional Citar integration and possible installed
artifact tests as passthru.tests. One coherent implementation commit was discussed.
The user prefers Cabal-style separation: project-owned test declarations/runners
should stay independent of Nix, with Nix supplying dependencies and invoking those
entry points. ERT and package metadata do not supply that same unified project
contract; a thin project-owned runner was discussed, not implemented.

The user's decision is to defer the broader testing refactor/migration.
None of the candidate directory moves, runner interfaces, checkPhase changes,
passthru tests or new installation tests are adopted work. The newly approved
cite-specific ert-cite-biblatex to ert-cite-export replacement is a separate,
bounded functional change, not resumption of this broader migration.
The current independent test derivations and shared Guile support stay as they are.
This is a non-blocking backlog item, not unfinished 0.8.0 release scope. Resume only
when the user explicitly reopens it; memory/backlog.md preserves the analysis,
constraints, alternatives and validation limits instead of an executable plan.
