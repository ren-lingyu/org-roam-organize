# Supported project design

## Package interface

The v0.6 baseline declares Emacs 30.1, Org 9.5 and Org-roam 2.3.1, with source and Nix metadata aligned. The dependency declaration is conservative rather than proof of every older supported combination. Removed legacy interfaces have no aliases; keybindings are examples owned by users.

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

The root flake composes a filtered source tree, packaged Emacs dependencies and test modules. Tests do not infer a parent-repository layout or depend on personal directories. ERT loads the installed package with real Org-roam; targeted function mocks remain useful without substituting a fake Org-roam object system.

The flake defines package build, ERT, package-lint and a development shell. Compilation warnings are errors. Nixpkgs is temporarily pinned to the revision containing the GNU ELPA Org hash-mismatch repair; the unstable URL remains commented for a later switch. That pin addresses a dependency fetch failure, not an application test failure.

## Citation model

Org source stores literature node UUID citations, with each literature node's single cite-type ROAM_REFS declaring its external bibliography key. Sync uses the UUID relationship; export changes only managed citation-reference keys in the parse tree and preserves source text and native processors.

The explicit cite-check command validates the global managed reference set without editing Org files. Cite-sync uses global relationship data and diagnostics. Missing/multiple refs block these operations; duplicate external keys remain nonblocking warnings at this stage.

Export first collects citation-reference keys from the actual export tree, intersects them with managed UUIDs, and validates/maps only that subset. Unrelated invalid literature must not block export. Non-managed external citations remain unchanged. Batch loading of mapping data avoids one database query per citation. A real export-pipeline ERT verifies downstream filters observe the converted key.

## Literature storage

The default literature example adopts a fixed ref.org inside the unique UUID bundle. Mutable bibliography keys or transliterated titles need not also serve as filenames. This is a useful convention enabled by configurable paths, not an instruction to rename every existing note or a universal filename requirement.

## Derived citation entries

Citation sync reconciles #+ROAM_CITING_NODE: ID-link keywords in managed literature notes through the shared MOC/ID-link machinery. It visits all managed references to remove stale entries, refreshes titles, preserves/reports duplicates and inserts missing citing nodes under the configured Inbox. Count distinct citing nodes rather than citation occurrences. The earlier ROAM_CITED_BY spelling was a proposal, not the adopted keyword.
