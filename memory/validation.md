# Evidence and validation

## Interpretation

This reconstruction uses committed source/README/test definitions, the eight
requested Codex archives and four handoff/reference documents. Whole available
record horizons were surveyed before selecting states, including inherited
conversation prefixes, compactions, retries and withdrawn turns. Shared source
material is counted once. The early pre-conversation repository interval is
already represented by earlier memory checkpoints.

The references are secondary evidence, not current instructions. Conversations
and ordinary-project `gaw-input/` are external inputs, not bundled evidence in
this workspace. Their useful conclusions are distilled here; resumption does
not require replaying raw logs. Other projects' results are not this project's
validation. No substantive unrecoverable interval has been identified within
the supplied material; undocumented early author intent remains unknown.

Earlier reconstruction wording counted an input-directory task list among the
supplied references. That attribution was not established, and the task list
is excluded as supporting evidence. Citar completion is supported by the
conversation records and committed implementation/tests instead.

Historical reports below refer to development candidates, often including
uncommitted changes. A nearby project commit does not prove that exact candidate
was tested. Project-parent associations here identify necessary static snapshot
inspection unless original exact-snapshot provenance is explicitly established.
No project build, test, GUI or dependency/network command is run by this
reconstruction. GAW checks validate protocol/workspace state, not project behavior.

## Reading earlier reconstructed states

Early snapshots describe superseded project models, including the fixed
file-organization workflow. Interpret their APIs, configuration and outstanding
work within their own evidence horizon; current project knowledge begins at
`memory/current.md`. Static observations made during retrospective review are
separate from decisions and runtime results documented in the original sessions.

The citation conversations share inherited material and later diverge. Their
start times do not establish development order: project ancestry places module
splitting before identity refactoring. The reconstruction preserves consequential
knowledge changes rather than treating each session or project commit as a
separate durable state. An ancestry relationship alone does not establish the
exact project baseline of a historical operation.

## Evidence for the represented transition

The final conversation reports passing nix flake check path:. --no-update-lock-file after the runner changes. An earlier suggestion to keep shell construction behind mkEmacsCheck was a proposal; the adopted implementation is executable Guile templates via replaceVarsWith. Static inspection of the final source/README/tests confirms the remembered contracts; no project checks were rerun during reconstruction.

Source scope: 01a08909-9416-7d41-8c15-471d32899279 and 01a08ada-6b2f-74a1-98d3-b251cb7c27f9, plus all earlier supplied source intervals.

## Continuing validation limits

The final source, README, module wiring and test definitions have been checked statically against this knowledge state. Historical check reports belong to their original candidates; this reconstruction ran GAW checks only. No current runtime certification, future Citar/Org compatibility guarantee, sidecar synchronization or replacement destructive deletion workflow is claimed. Title-display caches still require explicit refresh after indexed title changes, and arbitrary third-party state mutations are outside adapter restoration guarantees.

## Complete input horizon

The requested package-standardization session and long registry/capture/citation session supply the early feature evolution. The short testing session overlaps that work and supplies the independent test-infrastructure transition. The Citar session is inherited into both later citation sessions and is counted once. Their common continuation supplies bibliography/display/activation; their distinct tails supply module splitting and identity refactoring, ordered by project ancestry. The two final sessions supply runner proposals and the adopted implementation.

All eight requested conversation horizons and four handoff/reference documents have been considered within the accepted scope. The discovered input-directory task list is excluded as supporting evidence. Retries, compactions and withdrawn turns are not separate adopted states. References to another project are used only to explain this project's adopted testing/provider boundaries. No raw source archive or Auxiliary history is required to interpret the distilled memory, and no substantive unrecoverable interval has been identified. Undocumented early intent and exact committed baselines for historical uncommitted test candidates remain unknown.


## Later package and test migration validation

With explicit user permission, the agent ran formatting and flake validation on a
filtered copy of the uncommitted migration under ignored project tmp. All 38
relevant input files matched the copy after Nix formatting was synchronized back.
The final flake check passed on x86_64-linux: package build, all four ERT suites,
package-lint and treefmt. Other systems were omitted. No project lock update,
staging or commit was performed by the agent. This evidence describes the checked
uncommitted candidate, not exact committed-snapshot provenance for older tests.
Earlier statements that reconstruction ran no project checks apply to that
reconstruction activity, not this later authorized migration validation.

The final migration commit was inspected after the user moved HEAD. All relevant
files except flake.nix match the tested copy. Final flake edits remove the explicit
default package declaration and restyle equivalent attribute sets; checks were
not rerun by the agent on that final snapshot. Before checkpointing, the user
supplied successful `nix flake check` output (exit 0) from the clean committed
worktree on x86_64-linux. This supports the final state separately from the
agent-tested candidate. Its package output lists only the two named packages;
README's default-package claim needs a later correction. The project-parent
association identifies the inspected final snapshot.


## README alignment audit

The later README task used committed HEAD as its factual baseline and excluded
an independent unstaged flake.nix edit. The audit read the full README, inspected
its documented layout and package/test wiring, and checked public function,
registry, capture and citation claims against committed source. Corrections
cover named package outputs without a default, suite directory conventions,
the exactly-one-MOC requirement, the provider example preserving the existing
registry, and the main use-package example's closing parenthesis and hook name.
The hook spelling follows the official use-package Hooks manual at
https://www.gnu.org/software/emacs/manual/html_node/use-package/Hooks.html.

Read-only checks confirmed balanced delimiters in all nine Elisp blocks and the
existence of all nine referenced package functions at HEAD; git diff --check
passed. No example evaluation, build, test or formatter was run. The user
authorized staging only README.org and committed it; the new checkpoint parent
identifies that exact committed documentation snapshot. The earlier note about
README's stale default-package claim is superseded by this correction.


## 0.8.0 release-preparation validation

The user approved updating version metadata and README without preparing a
release draft or introducing CHANGELOG. The main Version header and Nix
version/melpaVersion changed from 0.7.0 to 0.8.0. README's new upgrade summary is
grounded in v0.7.0-to-current project history and the supported implementation;
existing registry/capture/MOC/UUID behavior is distinguished from newer citation
integrations and packaging changes. No dependency or lock refresh was performed.

With explicit command authorization, the candidate passed nix flake check
--no-write-lock-file on x86_64-linux, including four ERT suites, package-lint and
treefmt. Explicit nix build --no-link --no-write-lock-file --json succeeded for
both named package outputs. An isolated-HOME batch check verified installed
0.8.0 metadata, the generated Package-Version header, all nine modules resolving
inside the built package, eleven public commands and the autoload file. Loading
all modules neither enabled the mode nor loaded optional Citar. Default Emacs
was 31.1; this does not establish minimum-version, other-system or straight
installation compatibility. Project checks and builds had 120-second timeouts;
the installation runner had a 30-second timeout.

Initial smoke-script assumptions were corrected for this Nix JSON lacking
attrPath and MELPA replacing Version with Package-Version. These were temporary
verification-script issues; no product change was needed. Final checks passed.
The installed metadata/source checks do not evaluate user configuration or
exercise interactive capture against real notes.

Only the three preparation files were explicitly staged after user approval.
The user committed them, and read-only review confirmed the resulting commit
matches the tested candidate and the ordinary worktree is clean. The checkpoint
project parent identifies that exact inspected committed preparation state.
No tag, push or publication was performed by the agent. CHANGELOG remains a
separate possible follow-up involving historical release notes.


## First historical CHANGELOG

The user approved an English Org changelog backfilling 0.1.0-0.7.0 and explicitly
including v0.7.0-to-current-HEAD changes as Unreleased. Version/date headings use
direct release links and YYYY-MM-DD (UTC); no date or publication claim is assigned
to the prepared 0.8.0 candidate. Public GitHub release records were read through
the GitHub connector. Their seven published_at values supply the dates; local
and remote tag object IDs match. Existing release notes were read as supplementary
evidence, with entries checked against adjacent endpoint source trees and
historical READMEs, interfaces, dependency declarations and relevant tests.

Static checks covered all eight sections, category order and nonempty categories,
seven dates/URLs, eleven link targets and version-scoped project identifiers.
Tracked whitespace checking passed. For the new nonempty untracked file,
`git diff --no-index --check /dev/null CHANGELOG.org` produced expected status 1
without whitespace diagnostics; that status was explicitly accepted, while other
statuses would fail. The whitelist and staged/committed whitespace checks passed.
No builds, runtime tests, formatters or automated Org rendering were run.

The review report, separate from changelog prose, records two source-based
clarifications: the former command replaced by MOC sync was actually
org-roam-organize-update-mocs in 0.3.0, not the org-roam-organize-moc-update name
used in 0.4.0 notes; and 0.2.0's concise notes omitted details of keymap removal
and the declared Emacs minimum increase. The earliest 0.1.0 entry is only a
verified documented baseline without assigning every feature to that version.
No original hosted notes or historical source trees were modified.

Only CHANGELOG.org and .gitignore were staged after explicit authorization. The
user committed them. The committed changelog is byte-identical to the reviewed
candidate; the final ignore edit only regroups the equivalent whitelist entry.
The worktree is clean and the checkpoint's project parent identifies the exact
committed documentation state inspected after HEAD moved. README, versions,
implementation and lockfile were unchanged in this task.

## Committed Org summary/detail migration

Seven historical Org details and root metadata/navigation passed static inspection:
seven historical CLOSED records match peeled tag-commit committer epochs at UTC
minute precision; 18 local links resolve including migration/back links; 25 source
blocks balance; heading levels and unique per-file CUSTOM_ID values are valid;
50 project identifiers match their release/predecessor source or README. The user
manually applied DONE to historical entries and NEXT v0.8.0 with its ID. The user's
explicit instruction allowed the agent to write historical CLOSED despite the
skill's existing-entry time boundary; it grants no future state/time permission.

The user requested headline spacing cleanup, trailing-whitespace removal and
org-table-align. emacs -Q --batch aligned two tables and removed 26 blank lines
after headlines; a non-whitespace-content comparison excluded table-rule widths.
Source-block delimiters were lowercased, preserving arguments/body, and later user
Org editing added source indentation/escaping. Eight Emacs Lisp example blocks had
balanced parentheses/strings; no configuration example was executed. A local-path
backlink in v0.1.0 was fixed before staging, and all eight files were rechecked for
relative links, version IDs, UTC records, lowercase delimiters and headline spacing.
Tracked, staged and committed whitespace checks passed at the relevant steps.
Initial new-file no-index checks accepted status 1 only with no whitespace errors.

The user committed the docs, treefmt exclusions and strict .org ignore whitelist.
The final root-summary omission fix records ert-biblatex -> ert-cite-biblatex as
well as the Citar rename, matching committed README and check overlays. Read-only
inspection after the latest commit confirmed a clean ordinary worktree/index and
these final committed facts. The checkpoint project parent identifies that exact
reviewed final snapshot; no retrospective intermediate parent is inferred.

The user reported nix flake check failure before adding the root changelog treefmt
exclusion; no fresh Nix check/build was run after that fix. No full Org export or
render validation was run. Formatting is distinct from runtime validation. No
CHANGELOGS/v0.8.0.org or local v0.8.0 tag exists; no 0.8.0 publication is claimed.
No hosted notes or historical source trees were rewritten, and the agent did not
create ordinary project commits. Earlier package/runtime checks remain scoped to
the separately documented release-preparation candidate.

## Standalone historical release-note navigation (committed)

The user requested removal of top root-summary backlinks from all seven detail
files, to keep independent manuscripts usable after tag extraction/conversion and
historical successor-tag recovery. v0.1.0 was already edited by the user; the agent
removed the other six. Exact comparisons against project HEAD confirm every file
only loses that backlink and its following blank line. All 11 remaining root file
links resolve, including local migration IDs; CHANGELOG.org is unchanged and
worktree diff --check passed. The user then committed the seven-file removal;
read-only comparison of committed parent/new blobs matches the reviewed changes,
committed whitespace checking passes, and the ordinary worktree/index are clean.
No renderer, Nix check, publishing tool, or state/time mutation was run for this
narrow edit.

## Root input refresh and expanded formatting scope

The user committed three changes after the standalone-note checkpoint: refresh of
root nixpkgs/personal-nixpkgs locks, normalization of Org/gitignore presentation,
and removal of README.org, CHANGELOG.org, CHANGELOGS/*.org and .gitignore from
explicit treefmt exclusions. The project now explicitly excludes only LICENSE and
flake.lock and retains flakeCheck = true. Formatter selection/availability was not
evaluated; inclusion here describes the committed configuration.

Review read the complete flake manifest and lock graph and all three diffs. Only
the two root locked nodes changed; original input definitions, follows edges and
all transitive nodes are identical. Nine Org documents were compared against the
preceding project baseline: the actual diffs are keyword case, whitespace and
source comma escaping. A normalization comparison corroborates that review; it is
not an Org rendering test. State keywords and CLOSED values are unchanged. The
.gitignore nonempty pattern inventory is identical after regrouping; representative
root/detail documentation ignore checks confirm the files remain trackable.
All three commits pass git show --check; ordinary worktree/index are clean.

No Nix check/build, formatter execution, network dependency resolution or full Org
export was performed during this review. No result from the prior lock snapshot
is represented as validation of these new dependencies or the expanded treefmt
scope. The checkpoint associates the exact final project tree inspected, rather
than inferring separate intermediate checkpoint provenance. Historical 0.8.0 note
preparation and release-state boundaries remain unchanged.


## Unified cite export implementation validation

The user approved the implementation plan and required its planning memory
checkpoint first, followed by a manual project commit containing only NEXT -> TODO
for v0.8.0. Both boundaries were fulfilled before source changes. The candidate
was uncommitted when tested; later commit confirmation below establishes its exact
committed contents separately. Ordinary project commits and release transitions
remain human-owned.

The candidate scopes node/file/properties acquisition to exported keys, reuses the
existing ref validation query, converts AST identities, propagates opted-in paths,
and separates interactive library discovery from native/scoped export discovery.
The repair module and dedicated suite/configuration are replaced by generic export
coverage. README, docstrings and v0.8.0 summary describe the resulting behavior.
Historical release bodies, project dependency declarations and lockfile are unchanged.

A real basic-processor equivalence test exposed missing author/year output when
only info :bibliography was updated. Official oc-basic source and runtime evidence
show it obtains entries through org-cite-list-bibliography-files. The common advice
now provides the same dynamically bound resolved list through that interface;
there is no processor-specific production branch or persistent bibliography cache.
An early fixture failure also exposed shared quoted registry mutation; fixture
configuration is copied before mutation. A test call's body-only argument order
and an initial missing closing parenthesis were corrected before passing results.

Final validation ran in the filtered, task-owned tmp/cite-validation/project flake,
using the unchanged project manifest/lock and existing Nix/Guile test mechanism.
`nix flake check --no-write-lock-file path:/home/lingyu/Projects/org-roam-organize/tmp/cite-validation/project`
passed on x86_64-linux: package compilation/build, package-lint, treefmt, core ERT
90/90, Citar ERT 48/48, display ERT 13/13 and export ERT 8/8 (159 total).
The 45 selected project input files were byte-compared with the tested copy and
all matched. Complete project diff whitespace checking passed. Formatting changes
were applied from the isolated treefmt check's patch to the two affected Elisp
files, followed by the passing full check. No global formatter or system mutation
was performed. Other systems were omitted by Nix, not certified.

The new export suite uses real temporary Org-roam databases, literature properties
and bibliography files, with basic/ascii and biblatex/latex standard-input
comparisons. Coverage includes full/body-only, print/no-print, mixed/repeated/shared
paths, distinct bibliography files, native explicit/global paths including explicit
managed files, nil/missing opt-out with centralized bibliography, absent node
bibliography, excluded/include/macro citations, missing/multiple used refs and
unused invalid nodes, normal/error interactive restoration, native acquisition,
consecutive exports, lifecycle idempotence and unchanged source/modified state.
Changing a node's external key is observed after database sync without changing
the citing source. Citar/display existing regressions passed separately.

Native compatibility verification was also isolated by flake after the user
required that approach. Current Emacs 31.1/Org 9.8.7 passed native BibLaTeX
standard-input and parse-tree info propagation checks. An initial source-based
flake check passed those same checks with official Org release_9.5 at
73875939a8b5545ac53a86ec467239f510d14de8, generating only standard autoload/version
metadata in the Nix sandbox. No direct curl download was executed.

At the user's suggestion, historical nixpkgs was tried instead. Its 21.11 ELPA
Org 9.5 package could not be fetched because the upstream tar/tar.lz URLs returned
404; this is not a native export failure. Nixpkgs tag 22.05 at
ce6aa13369b667ac2542593170993504932eb836 provided cached Emacs 28.1 with builtin
Org 9.5.2, which passed both native checks with loaded-library paths confirmed.
This historical runtime validates native Org behavior, not full package support
on unsupported Emacs 28. The current native check uses flake-provided Emacs,
not the system executable. The user limited further historical research; no
additional search is needed and no project minimum version was changed.

All heavy checks had 120s timeouts; the earlier initial system-native probe had
30s and was superseded by the user's isolated-flake requirement. No PDF/Biber
compilation, minimum-Emacs full package run, other-system runtime validation,
interactive GUI workflow, release publication or installed-artifact smoke rerun
is claimed. Temporary artifacts are ignored under tmp and are not formal memory
dependencies. During implementation only the three new export-suite files were
authorized for agent staging. The user later staged the complete final candidate
and manually committed it after commit-message preparation.


### Committed candidate confirmation

The user committed the complete implementation after staging it. Read-only review
confirmed the expected cite commit, clean worktree/index, all 45 committed project
inputs byte-identical to the passing isolated snapshot, and absence of the four
obsolete repair-module/test files. Commit whitespace checking passes. The GAW
checkpoint's project parent identifies that exact inspected project snapshot.
The existing passing test evidence therefore applies to matching committed
contents; no new runtime check or additional platform certification is claimed.
The commit does not change the TODO release state or authorize publication.


## Committed single-file MOC transition

The complete implementation's 45 tracked manifest/source/package/test/doc inputs
are byte-identical to the final passing isolated snapshot. The subsequent
documentation commit changes only README.org; the other 44 inputs remain
identical. Read-only confirmation found a clean ordinary worktree/index and
passing committed whitespace checks. The README's complete diff was reviewed
against source, including the explicit alphanumeric-first ID alphabet and the
fact that UUIDs are one accepted Org ID format.

Full isolated validation used:
`timeout 120s nix flake check --no-write-lock-file
path:/home/lingyu/Projects/org-roam-organize/tmp/single-moc-validation/project`
on x86_64-linux with Emacs 31.1. Package compilation with warnings as errors,
package-lint, treefmt and all 200 ERT tests passed: core 131, Citar 48,
display 13, export 8. This was an actual test execution before the user committed.
Byte comparisons bind that evidence to the matching implementation contents;
the README follow-up itself was not part of that earlier run.

After committing the README, the user ran `nix flake check` in the clean current
project and provided exit 0 output with `all checks passed!`. All checks were
satisfied from cache (`running 0 flake checks`). This is valid successful check
evidence for the current inputs, not evidence of a fresh ERT execution. The four
ERT derivations are the same as those in the preceding actual 200-test run.
Other systems were explicitly omitted. The agent did not rerun project checks
merely to create the checkpoint.

### Coverage and important regressions

Registry/identity coverage includes invalid tags, literal percent-bearing tags,
plain-title parser round trips, effective target TODO syntax, required MOC
filetags, ID/path exclusivity to the MOC record and all four optional declaration
combinations. Real capture/DB fixtures check simultaneous constraints, moved
unconstrained paths, occupied IDs/targets, ambiguous tag nodes, join-row
deduplication, actual file ID/tag disagreement, capture abort and finalization,
preserved heads and idempotent creation.

Layout tests cover L1/L2/L3, different parents, strict title/CUSTOM_ID agreement,
duplicate/mixed/nested structure rejection, suspicious same-title unknown IDs
without automatically adopting manual text, and the final fixed level-1 MOC
Inbox policy. At L1 append to EOF; at L>1 insert before the active level-1
Inbox's first child, creating only that container at EOF if absent. Keep L
without intermediate levels. Duplicate active containers and unsafe new names
reject before modification.

Capture regressions preserve exact file/DB titles containing percent/date and
Org-roam placeholders, Lisp-like strings and marker prefixes. Structural
management text and filetags also remain literal. Other template fields retain
their native expansion behavior.

Regional tests cover level-0/MOC-file exclusion, cross-tag membership,
duplicates, stale removal, title refresh, :delete t, malformed diagnostics,
COMMENT/source exclusion, missing-region partial reporting, globally safe
edits across changing positions, multiple simultaneous insertions and no-op
idempotence. Property drawers, planning information and manual Inbox content
remain attached when the Inbox is childless or has children.

At most one active matching direct-child member Inbox is permitted per present
region, including empty/complete rosters. Any duplicate rejects the entire sync,
even when an earlier region already has edits planned, with zero saves/updates.
Default/custom names, deeper duplicates, other regions, COMMENT/source text and
no-Inbox/no-missing cases are covered. Cite/Citar/export/display regressions pass
without changing their production compatibility behavior.

### Scale and parse/save accounting

The reproducible core ERT moc-scale-ten-thousand-entries uses 10,000 entries in
four regions, real filesystem saves and DB refresh with controlled membership
lookup. Final observed first sync: 4.314s, one effective save and one DB update.
Unchanged sync: 2.503s, zero saves and updates. No timing threshold or hard node
limit is asserted.

The MOC planning pass parses the document once; individual entry values still
use temporary Org parsing and downstream DB refresh parses separately. Org-roam
may call save-buffer on an already unchanged buffer; effective-save counts do
not treat that as a second write.

The formatter ran in the isolated copy using `nix run --no-write-lock-file
path:<copy>#formatter.x86_64-linux -- --walk filesystem`. This Nix version
forwards nix fmt positional arguments and interprets the ignored nested flake
as an untracked Git path; the wrapper already selects the root via flake.nix.
Only authorized changed project files were copied back.

### Scope and continuation

The checkpoint's project parent identifies the exact inspected committed README
state, whose implementation matches the actual tested candidate and whose full
flake check the user subsequently confirmed from cache. It is a current-state
association, not retrospective proof that older intermediate candidates were
tested as commits. Relevant newly retained project history consists of shared
basic directories, entry primitives, single-file MOC and its README clarification;
their reviewed paths contain project code/tests/docs rather than raw sessions.

No real-note migration, destructive merge/deletion, GUI exercise, minimum-version
full package run or other-platform certification is claimed. User data migration
must preserve IDs/incoming links, :delete t, ordering and manual content, resolve
extra old MOC tags and move members into the declared CUSTOM_ID regions.
No release transition, dependency/lock change or publication occurred.

## nil Inbox implementation validation

The nil-Inbox feature was implemented on the uncommitted worktree candidate
based at the session's project HEAD. On x86_64-linux, `nix fmt` normalized the
candidate, core ERT ran 146 tests with 15 new nil-Inbox tests passing (registry
value matrix plus MOC sync cases for metadata, childless regions, EOF,
COMMENT first child, source blocks, skipped levels, Inbox preservation, policy
transitions, mixed policies and atomic failure), Citar 48, cite export 8 and
cite display 13 all passed, package-lint and treefmt passed, both named package
builds succeeded, and `nix flake check` exited 0. The user then committed the candidate as
`269b2a7d3eecc24c690cfdf32c2ca2a5ce201fb0` (feat(moc): support nil inbox for
member insertion). The committed tree is identical to the tested candidate:
its diff against the base commit is byte-identical (md5
3b6f928d59e32a0e7d9a1648c45b0777) to the staged diff that was verified, and
the ordinary worktree is clean. No check was re-run on the committed
snapshot itself; the tree-identity correspondence is the basis for the
checkpoint's project parent association.
