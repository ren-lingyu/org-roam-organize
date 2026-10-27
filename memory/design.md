# Supported project design

## Package interface

Source and Nix package metadata declare v0.7.0, with Emacs 30.1, Org 9.5 and Org-roam 2.3.1. Citar remains optional; 1.4.0 is the documented minimum tested backend version, with capability checks rather than a guarantee of future compatibility. Removed legacy interfaces have no aliases; user bindings remain examples.

## Organization

Registry records describe tag membership, MOC identity and relative node directories without hardcoded category names. Org files are authoritative; the Org-roam database and MOC views are derived. Names are safe short identifiers, exactly one :moc record identifies the map-of-maps role, and at most one :cite record identifies literature. A :basic record requires a directory; non-basic records may also have one. A usable directory selects ordinary creatable records.

The organizing root must stay inside org-roam-directory. Record paths are resolved inside that root without mutating user configuration. MOC destinations can be explicitly configured or derived from record names. Removed move/delete commands and aliases stay removed; :delete t remains a reserved marker, not an action.

## Setup and diagnostics

Setup combines variable/registry validation and runtime capabilities. The rejected blanket empty-string restriction is not restored; fields follow their own semantic validation.

Checks and sync commands collect complete report lines before presenting one result. Detailed warnings/failures go to *Org-roam Organize Report*, a read-only special-mode buffer overwritten by each new report. Successful commands without details use a short minibuffer summary. The formatter for notices is shared; business diagnostics are not an elaborate message-key registry. One command owns one final report, not an append-only history.

## MOC synchronization

Managed membership is represented by #+ROAM_NODE: ID-link keywords, not generated headings. Org-element parsing avoids treating source/example text or commented content as live entries. Existing valid entries keep their relative positions; titles are refreshed, stale entries removed, and missing members inserted under the configured top-level Inbox.

Duplicate entries are all synchronized and reported, not silently deduplicated. Malformed entries are diagnosed. The :delete t marker is preserved but does not perform deletion. Managed statistics are written separately from membership synchronization. The old public MOC update command is replaced by global MOC sync.

## Capture and templates

Ordinary providers receive a registry record and return (:title TITLE :info INFO), or nil to cancel. Missing/nil :provider uses the default. MOCs use a separate internal provider with the same request protocol. The core constructs nodes and controls paths, targets, templates and lifecycle.

Structured :template sections include path, properties and keywords. Native ${field} and %<FORMAT> expand at capture time. The path is relative inside <directory>/${id}/, defaults to ${slug}.org, may contain nested directories, must end in .org and must remain lexically inside that UUID bundle. MOC destinations use their own path rule and do not accept ordinary node path overrides.

The preface hook creates directories only after placeholders expand. Cleanup tracks the UUID bundle root rather than the final target's immediate parent. Empty abandoned bundles are removed; removing a nonempty abandoned bundle requires confirmation. Self-removing finalize hooks outlive the capture call and are removed on errors.

## Testing architecture

The root flake uses the personal-nixpkgs framework with a source fileset rooted
at `lisp/`. `pkgs/` contains package.nix/overlay.nix pairs discovered through
packages.mkOverlays. The library uses melpaBuild, v0.7.0 metadata, Org and Org-roam
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
directories. Existing check attributes remain unchanged. Tests use real
dependencies, temporary databases and targeted mocks. Citar is added only to its
suite. Package modules declare package-lint-main-file; lint recursively checks
all packaged Elisp files and gets the explicit source working directory/load-path.

The ERT builder and Guile runner are shared under tests/support. replaceVarsWith
creates executable runners with explicit Guile, Emacs and test/source inputs.
Test-file interpolation retains Nix dependency context; toString on the path does
not. Guile system* passes argument lists, isolates HOME under the build temporary
directory, propagates failures and creates the output marker only after success.
Scheme files are whitelisted by Git ignore rules. Treefmt is included in checks.
Nixpkgs follows unstable; lock refreshes are dependency maintenance.


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

The BIBLIOGRAPHY property on managed level-0 literature nodes supplies paths relative to each note file. Each enabled discovery request queries indexed nodes.properties, resolves paths, deduplicates and sorts without another persistent cache. It neither reads nor validates bibliography files and does not create/synchronize sidecars. Saved property changes require database synchronization before discovery sees them.

Mode-owned filter-return advice appends managed paths to org-cite-list-bibliography-files, preserving existing first-occurrence order/precedence. Citar and export processors consume that common result; the former Citar-specific local-bibliography override is retired. The package does not select a citation export processor, overwrite citar-bibliography or insert print_bibliography for users.

## BibLaTeX compatibility

The internal org-roam-organize-cite-biblatex module provides the mode-owned final-output fallback, enabled only with :bibliography t. It applies to LaTeX-derived biblatex exports containing a managed bibliography and adds only missing direct package/resource declarations before begin{document}. Body-only/unrelated exports remain unchanged; printbibliography and processor selection stay user-owned.

Actual final output determines whether upstream already succeeded. Options/style merging delegates to Org's helper, avoiding duplicate brackets or reimplemented precedence. Teardown removes the filter, and failed setup rolls back ownership.

## Citation display

The backend-independent org-roam-organize-cite-display module displays titles for recognized managed UUID citation keys using owned overlays. Source text, modified state and citation prefix/suffix structure remain intact. It composes through Org's extra Font Lock keywords rather than replacing org-cite-activate-processor. It activates with the core mode and a :cite record, independently of bibliography opt-in or Citar.

Per-buffer title caching avoids repeated database queries. An explicit refresh clears caches/owned overlays after node titles or membership change; there is no automatic cross-buffer database invalidation contract. Global setup rebuilds Font Lock defaults in existing Org buffers as well as registering future-buffer hooks. Refresh widens for full cleanup/fontification and restores narrowing, point and buffer state.

Changing major mode removes local ownership state before it is lost. Teardown removes only this module's overlays/hooks. Buffers with Font Lock disabled remain disabled: defaults may be rebuilt, but eager fontification runs only when enabled. The disabled state must not be inferred solely from batch-mode behavior.

## Citar activation

Around Citar's basic Org Cite activation only, resolve UUID candidates in the current citation, copy the active entry hash lazily and add aliases to the corresponding external entries. Dynamically bind citar--entries for that one call. No projection is retained, so later activation sees current mappings and bibliographies.

This follows a documented internal Citar contract and remains capability-checked; it is not a universal public mapping API. The wrapper calls the original function exactly once. Mapping/projection failure warns and falls back to ordinary Citar activation rather than interrupting Font Lock. Citation objects, source text and Citar's original entry table remain unchanged. Actions, insertion, file/link sources and notes continue using their own conversion policies.

## Modules and migration

The public entry remains (require 'org-roam-organize). Core holds registry/configuration/shared diagnostics, capture owns creation, entry owns shared keyword parsing/reconciliation, MOC owns MOC operations, and cite owns citation behavior. Tests and packaging include the corresponding modules explicitly. Shared entry logic is below both MOC and cite so core does not require higher-level citation behavior.

Old org-roam-organize-citar and org-roam-organize-biblatex features/files are removed. Explicit feature consumers use org-roam-organize-cite-citar and org-roam-organize-cite-biblatex. Their implementation symbols use internal -- namespaces. Former setup/teardown/dwim names, even those previously lacking --, have no supported public replacement; remove direct calls/bindings and select the Citar adapter through the registry/mode lifecycle.

The reserved Citar notes-source symbol becomes org-roam-organize-cite-citar. Direct users must migrate it. Nix attributes become ert-cite-citar and ert-cite-biblatex. No file/feature/symbol aliases are provided, and normal users need not require implementation modules directly.

## Citation identity implementation

Shared primitives live in org-roam-organize-cite, not an unscoped lib module. The row-to-map function retains candidate lists in both UUID-to-citekeys and citekey-to-UUIDs directions, preserving first-occurrence order. It normally deduplicates identity pairs; a duplicate-preserving mode lets global diagnostics retain raw declaration multiplicity symmetrically.

One managed identity loader restricts by tag and level-0 cite refs, with all/UUID/citekey selectors. An empty restricted key set returns empty maps without a database query. SQL vectors use explicit vector construction. Pure row transformation is separate from database acquisition.

Consumers retain their distinct strict, tolerant, plural or diagnostic policies: insertion needs a unique reverse match, actions need a unique forward match, notes may return lists, activation tolerates missing data, sync reports appropriate quality warnings, and export stays local to its cited UUIDs. Sharing acquisition does not make all boundaries enforce a bijection. Both directions are built intentionally; a future optimization must preserve order, multiplicity and scope.
