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

The root flake injects a filtered source tree, installed package and Emacs environments into independent test modules. ERT uses real Org-roam, temporary databases and targeted mocks. Separate core and Citar ERT environments keep the optional backend optional. Package build, lint and development shell are wired explicitly; compilation warnings remain errors. Nixpkgs has returned to unstable after the earlier Org-fetch workaround.

## Citation model

Org source stores literature UUID citations; cite-type ROAM_REFS supplies each node's external bibliography key. Sync derives citing-node entries by UUID. Export maps only the managed UUIDs present in the export parse tree, preserving source text, ordinary citations and native processors.

Mapping must preserve multiplicity until a consumer applies its own rule. Global cite-check now requires a bijection: every managed literature node has exactly one cite ref and every external key belongs to at most one node. Cite-sync may still report duplicate external keys as nonblocking when UUID relationships are unambiguous. Export validates only cited managed nodes. Do not substitute one direction's uniqueness rule for all consumers.

## Literature storage

The default literature example adopts a fixed ref.org inside the unique UUID bundle. Mutable bibliography keys or transliterated titles need not also serve as filenames. This is a useful convention enabled by configurable paths, not an instruction to rename every existing note or a universal filename requirement.

## Derived citation entries

Citation sync reconciles #+ROAM_CITING_NODE: ID-link keywords in managed literature notes through the shared MOC/ID-link machinery. It visits all managed references to remove stale entries, refreshes titles, preserves/reports duplicates and inserts missing citing nodes under the configured Inbox. Count distinct citing nodes rather than citation occurrences. The earlier ROAM_CITED_BY spelling was a proposal, not the adopted keyword.

## Citar adapter

The unique :cite record selects :backend citar; no backend or nil leaves Citar integration uninstalled. The previous separate backend custom variable is removed. Capability validation and dispatch remain distinct from merely reading registry selection.

At-point actions translate UUIDs to external keys before handing control to Citar. Citar insertion and its Org Cite insert processor require distinct adaptation boundaries so both produce UUID source citations. Missing/ambiguous mappings error explicitly; ordinary non-UUID citations keep standard behavior. Citar's own key-at-point parser is not repurposed to rewrite stored identity.

Mode setup/teardown owns the adapter. Setup validates selected configuration and Citar capabilities, rolls back partially installed advice/state on failure, and degrades to core-only operation rather than disabling successful core setup or removing its export filter. Citar is not a mandatory core dependency.
