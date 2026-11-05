# Supported project design

## Package interface

Source and Nix package metadata declare v0.8.0, with Emacs 30.1, Org 9.5 and Org-roam 2.3.1. Citar remains optional; 1.4.0 is the documented minimum tested backend version, with capability checks rather than a guarantee of future compatibility. Removed legacy interfaces have no aliases; user bindings remain examples.

## Release history documentation

The adopted Org profile keeps curated English summaries in CHANGELOG.org and
complete historical release notes in CHANGELOGS/<tag>.org. Seven historical versions
v0.1.0-v0.7.0 are DONE with matching CUSTOM_ID and UTC CLOSED. The user manually
returned the candidate to TODO v0.8.0 with matching ID; its complete detailed manuscript
has not been written, and it has no CLOSED/publication claim. Existing state
transitions and version-time changes remain human-owned except for the user's
explicit one-task historical CLOSED authorization already exercised.

Historical CLOSED values use peeled tag-commit committer epochs converted to UTC
at minute precision, not hosting publication dates. Root declares native TODO states,
logdone and TIMEZONE UTC. A file property alone does not make Org log times in UTC.
Root-to-detail and migration links provide stable navigation. Details are standalone
authoritative manuscripts and contain no root-summary backlinks. This avoids requiring
link rewriting during later extraction/conversion or a matching root summary in the
successor snapshot used for historical backfill. This user-adopted policy supersedes
the former temporary backlink retention; remaining file links use relative paths.
Formatting uses no blank after headlines, lowercase Org keyword names and block delimiters,
no trailing whitespace and org-table-align tables.

Record notable user-visible additions, behavior changes, fixes and incompatible
interfaces. Omit internal-only work and empty categories. Breaking entries include
migration guidance. Released source behavior governs; old hosted notes are
supplementary. Evidence conflicts belong in reports/memory, not user-facing history.
README remains the current-use/configuration guide. The 0.8.0 summary and README
both record ert-citar -> ert-cite-citar and ert-biblatex -> ert-cite-export.

README.org, CHANGELOG.org, CHANGELOGS/*.org and .gitignore are now in treefmt's
configured scope; only LICENSE and flake.lock remain explicitly excluded in the
project flake. flakeCheck remains enabled. This supersedes the historical Org
exclusions. The Git whitelist permits CHANGELOGS/*.org; root-file exceptions are
grouped before directory groups and *~ is last. For future profile releases, the complete detailed file
from the release tag is the sole Release Notes manuscript; root is a summary, not
a publishing fallback. Conversion/publication tooling remains separate. Legacy
backfill follows the skill's confirmed successor-tag source selection; reviewed
mainline fallback needs explicit authorization. Do not rewrite old tags or silently
replace existing hosted notes.

## Organization

Registry records describe tag membership, MOC identity and relative node directories without hardcoded category names. Org files are authoritative; the Org-roam database and MOC views are derived. Names are safe short identifiers, exactly one :moc record identifies the map-of-maps role, and at most one :cite record identifies literature. A :basic record requires a directory; non-basic records may also have one. A usable directory selects ordinary creatable records.

The organizing root must stay inside org-roam-directory. Record paths are resolved inside that root without mutating user configuration. Basic records may share directories. Only the unique MOC record declares an optional :moc-id and :moc-path; all explicit declarations are simultaneous constraints on the uniquely tagged level-0 file node. Its default <directory>/<name>.org target applies only to creation and does not constrain later moves within root. Removed move/delete commands and aliases stay removed; :delete t remains a reserved marker, not an action.

## Setup and diagnostics

Setup combines variable/registry validation and runtime capabilities. The rejected blanket empty-string restriction is not restored; fields follow their own semantic validation.

Checks and sync commands collect complete report lines before presenting one result. Detailed warnings/failures go to *Org-roam Organize Report*, a read-only special-mode buffer overwritten by each new report. Successful commands without details use a short minibuffer summary. The formatter for notices is shared; business diagnostics are not an elaborate message-key registry. One command owns one final report, not an append-only history.

## MOC synchronization

The committed single-file model supersedes the former per-record MOC files. There is one uniquely tagged level-0 file node, with a mandatory file ID and a MOC template explicitly containing its tag in filetags. The template cannot write ID. All registry tags must use Org's nonempty alphabet of letters, digits and _@#%; whitespace, colons, hyphens and controls are rejected. Tag join rows are deduplicated by node ID, explicit ID/path constraints are checked together, and occupied creation targets/IDs or ambiguous tags block creation without fallback. Commands also check the actual file-level ID/tag before modifying it.

The optional MOC ID must begin with an alphanumeric character and contain only alphanumeric characters or _.:@+-. UUIDs of any version satisfy this format; UUIDs are one form of accepted Org ID, not a separate identity mechanism. Omit the declaration for automatic capture generation or retain the existing file-level ID when migrating.

Each non-MOC record owns one management headline with CUSTOM_ID equal to :tag and title matching :moc-title or the derived name. All titles are nonblank control-free single lines. Management titles must round-trip through Org's parser to identical raw values, without TODO/priority/COMMENT/trailing-tag or footnote-section semantics; new regions are also preflighted against effective target TODO keywords. The MOC record has no region or own member index. Duplicate IDs, COMMENT regions, title mismatches or mixed/nested management levels reject preflight. Regions must share a level but can have different parents.

Creation defaults to L1 and otherwise inherits the common level L. At L1 append missing management headlines at EOF. For every L>1, the MOC record's :inbox names a level-1 container independent of L. Locate it and its first child using the existing AST; insert after introductory text/properties and before the first child, or at its end when childless. If absent, create a level-1 Inbox at EOF. Preserve level L without adding intermediate levels 2..L-1. Duplicate active level-1 Inboxes reject preflight, and a new Inbox name must pass plain-headline/target-TODO validation. COMMENT/source text and nested same-name headings are not container candidates. Creation preserves existing heads/content and does not sync members.

When a region is missing, a non-commented same-title headline with an unregistered CUSTOM_ID (including empty) outside known managed subtrees is ambiguous and rejects preflight. Title alone does not establish identity: no-CUSTOM_ID handwritten titles, manual children of known regions, valid known identities despite unrelated same-title content, and records sharing a declared title but using distinct tags are preserved. No suspicious headline is automatically adopted or repaired.

Every present management region may have at most one active matching direct-child member Inbox at L+1. Sync checks uniqueness even for empty or complete rosters. Any duplicate rejects the whole sync before edits/save/DB refresh; deeper same-title headings, COMMENT/source text and other regions' Inboxes do not count. Zero matches create nothing unless members are missing. A shared AST lookup returns the validated Inbox, and insertion uses its first child or subtree end, never contents-begin. Thus childless Inbox property drawers, planning metadata and handwritten content remain attached, and entries append after them. Cite's global file compatibility path retains its own prior behavior.

Initial management text is inserted literally before capture finalization. The MOC file title uses a collision-free marker restored to its exact declared value, and filetag percent signs are temporarily protected/restored, so structural titles and tags are not changed by capture expansion. Other template fields keep native expansion.

Membership remains #+ROAM_NODE: ID-link keywords within each region, including manual subsections. Only tagged level-0 nodes outside the MOC file are members. COMMENT/source text is excluded. Existing entries retain relative order, titles update, stale entries disappear, malformed lines remain and are reported, and duplicate entries plus :delete t semantics are preserved per region. A node can appear in multiple tag regions. Missing members go to a region-local direct child :inbox at L+1, before its children. Missing regions are reported by sync while other valid regions can proceed; sync does not create regions.

MOC sync reuses one document AST, per-region entry plans, globally descending existing edits and advancing insertion markers cleaned with unwind-protect. Unchanged text is not rewritten. Changed files are saved and DB-refreshed once; unchanged files are neither saved nor refreshed. Individual entry values still use temporary Org parsing, and the downstream DB refresh has its own parse. Cite retains the original file/global-Inbox compatibility wrapper. The old per-record mapping, managed tag/count properties/configuration and :moc_managed_tag capture info are removed. Old data migration is manual: preserve file IDs/incoming links and handwritten content, move members to tagged CUSTOM_ID regions, remove extra map tags and sync the DB. No old files or user properties are deleted automatically.

## Capture and templates

Ordinary providers receive a registry record and return (:title TITLE :info INFO), or nil to cancel. Missing/nil :provider uses the default. MOCs use a separate internal provider with the same request protocol. The core constructs nodes and controls paths, targets, templates and lifecycle.

Structured :template sections include path, properties and keywords. Native ${field} and %<FORMAT> expand at capture time. The path is relative inside <directory>/${id}/, defaults to ${slug}.org, may contain nested directories, must end in .org and must remain lexically inside that UUID bundle. MOC destinations use their own path rule and do not accept ordinary node path overrides.

The preface hook creates directories only after placeholders expand. Cleanup tracks the UUID bundle root rather than the final target's immediate parent. Empty abandoned bundles are removed; removing a nonempty abandoned bundle requires confirmation. Self-removing finalize hooks outlive the capture call and are removed on errors.

## Testing architecture

The root flake uses the personal-nixpkgs framework with a source fileset rooted
at `lisp/`. `pkgs/` contains package.nix/overlay.nix pairs discovered through
packages.mkOverlays. The library uses melpaBuild, v0.8.0 metadata, Org and Org-roam
dependencies and compilation warnings as errors. The wrapper uses default Emacs;
the user rejected selecting Emacs 31 in the flake. Named library and Emacs wrapper
package outputs are declared; the final migration commit removes the explicit
default package declaration. The final flake-check output lists only the named
library and Emacs wrapper. README now documents explicit named-package builds.
Its straight recipe selects lisp/*.el. The configuration example has balanced
registry syntax and the standard use-package after-init hook spelling. The
provider example adds a record to a valid registry rather than removing its
required MOC record.

Tests are discovered through tests.mkChecks and test-overlay.nix, with test.nix
per leaf. Core ERT is under tests/ert; citation suites have separate ert-cite-*
directories. The old ert-cite-biblatex check is replaced by ert-cite-export; other check
attributes remain unchanged. Tests use real
dependencies, temporary databases and targeted mocks. Citar is added only to its
suite. Package modules declare package-lint-main-file; lint recursively checks
all packaged Elisp files and gets the explicit source working directory/load-path.

The ERT builder and Guile runner are shared under tests/support. replaceVarsWith
creates executable runners with explicit Guile, Emacs and test/source inputs.
Test-file interpolation retains Nix dependency context; toString on the path does
not. Guile system* passes argument lists, isolates HOME under the build temporary
directory, propagates failures and creates the output marker only after success.
Scheme files are whitelisted by Git ignore rules. Treefmt is included in checks.
Nixpkgs follows unstable; lock refreshes are dependency maintenance. The current
refresh changes only root nixpkgs and personal-nixpkgs locks; original input URLs,
personal-nixpkgs following root nixpkgs and all transitive lock nodes are unchanged.
README, root/detail Org changelogs and .gitignore participate in the configured
treefmt scope. A dependency refresh requires fresh validation before carrying
forward earlier runtime/build success claims.


## Unified cite export

The implementation converts managed UUID citations and optional bibliography
metadata into standard Org Cite input without modifying source. Preserve tag-based
level-0 membership, one cite-type ROAM_REFS per cited managed node, scoped export
validation and the global bijection check. Unmanaged keys remain unchanged.

Only literal :bibliography t enables interactive full-library discovery and
export-time cited-node propagation. Nil/missing disables both while UUID conversion
still works with ordinary document/global bibliography configuration. Missing node
bibliography is not an error. No processor or print_bibliography is selected.

Mode-owned org-export-as around advice dynamically binds an export context and
initially unresolved bibliography. Before transformation, native acquisition has
no managed expansion. The parse-tree filter collects unique keys after standard
preprocessing/pruning, queries only matching managed nodes with file/properties,
and uses existing reference-map validation. Node acquisition does not join refs,
so missing-ref nodes survive for validation. Keep raw declaration multiplicity
until validation. Unreferenced invalid nodes do not block export.

The filter rewrites AST keys and appends opted-in paths to info :bibliography.
Preserve native order, then append sorted/deduplicated absolute paths resolved
relative to each literature file. Interactive discovery shares path resolution.
Explicitly configured managed paths must not be subtracted. No literature-file
reads, global bibliography checks or persistent export cache are introduced.
File-level property drawers belong at the top of examples.

Native oc-basic queries discovery for citation entries, so info-only propagation
is insufficient. After transformation, common discovery advice exposes the same
resolved per-export bibliography. Dynamic bindings restore state after success,
errors and nested calls; advice is never removed/reinstalled during an export.
This handling is independent of processor identity. Later third-party parse-tree
mutations require compatible filter ordering.

The bundled BibLaTeX module and repair suite/configuration are removed after
native-input and real standard-equivalence validation. ert-cite-export uses the
existing independent Nix/Guile runner, temporary Org-roam databases/bibliographies
and basic/biblatex exports. Broader test migration remains deferred. See
memory/validation.md for exact coverage and limitations.

## Citation model

Org source stores literature UUID citations; cite-type ROAM_REFS supplies each node's external bibliography key. Sync derives citing-node entries by UUID. Export maps only the managed UUIDs present in the export parse tree, preserving source text, ordinary citations and native processors.

Mapping must preserve multiplicity until a consumer applies its own rule. Global cite-check now requires a bijection: every managed literature node has exactly one cite ref and every external key belongs to at most one node. Cite-sync may still report duplicate external keys as nonblocking when UUID relationships are unambiguous. Export validates only cited managed nodes. Do not substitute one direction's uniqueness rule for all consumers.

## Literature storage

The default literature example adopts a fixed ref.org inside the unique UUID bundle. Mutable bibliography keys or transliterated titles need not also serve as filenames. This is a useful convention enabled by configurable paths, not an instruction to rename every existing note or a universal filename requirement.

## Derived citation entries

Citation sync reconciles #+ROAM_CITING_NODE: ID-link keywords in managed literature notes through the shared MOC/ID-link machinery. It visits all managed references to remove stale entries, refreshes titles, preserves/reports duplicates and inserts missing citing nodes under the configured Inbox. Count distinct citing nodes rather than citation occurrences. The earlier ROAM_CITED_BY spelling was a proposal, not the adopted keyword.

## Citar adapter

The unique :cite record selects :backend citar; nil/missing backend leaves the adapter uninstalled. Core UUID synchronization/export is backend-independent. Adapter setup is mode-guarded, validates capabilities and rolls back partial installation; optional failure warns while core mode remains enabled.

Both insertion paths translate external keys to UUIDs; at-point actions translate UUIDs back. Missing/ambiguous mappings are errors and ordinary citations retain their behavior. The adapter registers its own formal Citar notes source with :items, :hasitems, :open and :create. Lookup is limited to citation-tagged level-0 nodes and cite refs; a snapshot predicate avoids repeated hasitems queries.

Creation consumes Citar's (citekey entry) callback directly, never reselecting the key or invoking the ordinary registry provider. Existing single matches are refused rather than silently opened/modified; multiple matches are ambiguous. The managed capture template must carry the citation tag and must not manually write ROAM_REFS. A successful-finalize callback adds the cite ref, saves and updates the database; abort/failure does not register an incomplete note. Core capture runs success callbacks in the capture buffer and removes temporary hooks on errors.

Setup rejects a notes-source name collision. Teardown unregisters owned state and restores prior source/at-point selection only while the adapter still owns those settings. It does not promise to repair arbitrary user mutations after installation. Public dispatch is capability-checked and tested through citar-create-note.

## Citar formatting

The citation record's :backend accepts a symbol or a tagged (citar OPTION VALUE...) specification. Core accessors separate backend identity from options; only Citar interprets :title and :info formatting. Options reject malformed, unknown or duplicate keys rather than silently guessing.

With the simple citar symbol, title defaults to the entry title and falls back to citekey when blank. Tagged :info maps user-chosen keywords to Citar format strings; no fixed author/year/DOI schema is imposed. Citar formatting uses the callback entry and its configured available fields. Provider-style :title/:info is then passed to managed capture, leaving the success-finalize ROAM_REFS contract intact. Backend formatting and ordinary :provider selection are separate paths.

## Bibliography

Only literal :bibliography t on the unique :cite registry record enables managed bibliography integration; missing/nil leaves existing discovery unchanged. Restart the mode after changing this setup-time option. Bibliography policy is independent of :backend citar and does not control UUID sync/export identity.

The BIBLIOGRAPHY property on managed level-0 literature nodes supplies paths relative to each note file. Each enabled interactive discovery request queries indexed nodes.properties, resolves paths, deduplicates and sorts without another persistent cache. It neither reads nor validates bibliography files and does not create/synchronize sidecars. Saved property changes require database synchronization before discovery sees them.

Mode-owned filter-return advice extends interactive org-cite-list-bibliography-files
with the full managed library, preserving first-occurrence precedence. During
export it preserves native acquisition, then exposes the resolved scoped list,
matching info :bibliography. The Citar-specific discovery override remains retired.
The package does not choose a processor, overwrite citar-bibliography or insert
print_bibliography.

## Native citation processor ownership

There is no bundled BibLaTeX repair layer or processor-specific export production
code. Native processors own rendering, styles and package/resource declarations.
Remove old compatibility-library requires/calls and use ordinary Org Cite settings.
Full/body-only and print/no-print behavior is covered by real exports.

## Citation display

The backend-independent org-roam-organize-cite-display module displays titles for recognized managed UUID citation keys using owned overlays. Source text, modified state and citation prefix/suffix structure remain intact. It composes through Org's extra Font Lock keywords rather than replacing org-cite-activate-processor. It activates with the core mode and a :cite record, independently of bibliography opt-in or Citar.

Per-buffer title caching avoids repeated database queries. An explicit refresh clears caches/owned overlays after node titles or membership change; there is no automatic cross-buffer database invalidation contract. Global setup rebuilds Font Lock defaults in existing Org buffers as well as registering future-buffer hooks. Refresh widens for full cleanup/fontification and restores narrowing, point and buffer state.

Changing major mode removes local ownership state before it is lost. Teardown removes only this module's overlays/hooks. Buffers with Font Lock disabled remain disabled: defaults may be rebuilt, but eager fontification runs only when enabled. The disabled state must not be inferred solely from batch-mode behavior.

## Citar activation

Around Citar's basic Org Cite activation only, resolve UUID candidates in the current citation, copy the active entry hash lazily and add aliases to the corresponding external entries. Dynamically bind citar--entries for that one call. No projection is retained, so later activation sees current mappings and bibliographies.

This follows a documented internal Citar contract and remains capability-checked; it is not a universal public mapping API. The wrapper calls the original function exactly once. Mapping/projection failure warns and falls back to ordinary Citar activation rather than interrupting Font Lock. Citation objects, source text and Citar's original entry table remain unchanged. Actions, insertion, file/link sources and notes continue using their own conversion policies.

## Modules and migration

The public entry remains (require 'org-roam-organize). Core holds registry/configuration/shared diagnostics, capture owns creation, entry owns shared keyword parsing/reconciliation, MOC owns MOC operations, and cite owns citation behavior. Tests and packaging include the corresponding modules explicitly. Shared entry logic is below both MOC and cite so core does not require higher-level citation behavior.

Old org-roam-organize-citar and org-roam-organize-biblatex features/files are removed. Explicit Citar consumers use org-roam-organize-cite-citar; old and transitional BibLaTeX features are absent. Their implementation symbols use internal -- namespaces. Former setup/teardown/dwim names, even those previously lacking --, have no supported public replacement; remove direct calls/bindings and select the Citar adapter through the registry/mode lifecycle.

The reserved Citar notes-source symbol becomes org-roam-organize-cite-citar. Direct users must migrate it. Nix attributes become ert-cite-citar and ert-cite-export. No file/feature/symbol aliases are provided, and normal users need not require implementation modules directly.

## Citation identity implementation

Shared primitives live in org-roam-organize-cite, not an unscoped lib module. The row-to-map function retains candidate lists in both UUID-to-citekeys and citekey-to-UUIDs directions, preserving first-occurrence order. It normally deduplicates identity pairs; a duplicate-preserving mode lets global diagnostics retain raw declaration multiplicity symmetrically.

One managed identity loader restricts by tag and level-0 cite refs, with all/UUID/citekey selectors. An empty restricted key set returns empty maps without a database query. SQL vectors use explicit vector construction. Pure row transformation is separate from database acquisition.

Consumers retain their distinct strict, tolerant, plural or diagnostic policies: insertion needs a unique reverse match, actions need a unique forward match, notes may return lists, activation tolerates missing data, sync reports appropriate quality warnings, and export stays local to its cited UUIDs. Sharing acquisition does not make all boundaries enforce a bijection. Both directions are built intentionally; a future optimization must preserve order, multiplicity and scope.
