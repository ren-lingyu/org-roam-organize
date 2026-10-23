# Supported project design

## Package interface

The v0.4 development interface declares Emacs 30.1, Org 9.5 and Org-roam 2.3.1. Org-roam's capture target behavior is an explicit dependency; the declaration is conservative rather than a measured minimum across older releases. Removed legacy commands and variables have no aliases; keybindings remain user-owned examples.

## Organization

Registry records describe tag membership, MOC identity and node directories without hardcoded category names. Org files remain authoritative, with the database and MOC views derived from them. A basic record requires a directory; directory-bearing non-basic records are now allowed. Ordinary creatable records are selected by a usable directory, not by :basic alone.

MOC paths/titles are resolved from registry data without modifying it. Fixed fleeting/permanent semantics and the old move/delete interface remain removed. No replacement destructive deletion command has been adopted.

## Setup and diagnostics

Setup combines configuration validation and runtime capability checks through one diagnostic result. Deprecated settings are excluded from startup requirements. The user rejected an unrelated tightening that treated every empty string as invalid; do not silently restore that policy.

## MOC synchronization

Managed membership is represented by #+ROAM_NODE: ID-link keywords, not generated headings. Org-element parsing avoids treating source/example text or commented content as live entries. Existing valid entries keep their relative positions; titles are refreshed, stale entries removed, and missing members inserted under the configured top-level Inbox.

Duplicate entries are all synchronized and reported, not silently deduplicated. Malformed entries are diagnosed. The :delete t marker is preserved but does not perform deletion. Managed statistics are written separately from membership synchronization. The old public MOC update command is replaced by global MOC sync.

## Capture and templates

An ordinary provider receives its registry record and returns (:title TITLE :info INFO), or nil to cancel. Missing/nil :provider selects the built-in default provider. The core constructs the Org-roam node and owns paths, target, template and directory lifecycle; providers do not return arbitrary nodes or control filesystem placement.

Structured template sections separate properties from keywords. Property drawers and file keywords are serialized into capture text. Native ${field} expansion consumes provider :info, and %<FORMAT> expands at capture time. Do not build a second interpolation engine or freeze dates during configuration evaluation. MOCs use an internal provider implementing the same request protocol, independently of the record's ordinary custom provider.

Ordinary targets remain <directory>/${id}/${slug}.org, and MOCs retain configured destinations. Temporary templates are passed directly to capture, not registered globally. The earlier dynamically scoped cleanup hook is still a known lifecycle limitation.

## Testing architecture

The root flake composes a filtered source tree, packaged Emacs dependencies and test modules. Tests do not infer a parent-repository layout or depend on personal directories. ERT loads the installed package with real Org-roam; targeted function mocks remain useful without substituting a fake Org-roam object system.

The flake defines package build, ERT, package-lint and a development shell. Compilation warnings are errors. Nixpkgs is temporarily pinned to the revision containing the GNU ELPA Org hash-mismatch repair; the unstable URL remains commented for a later switch. That pin addresses a dependency fetch failure, not an application test failure.
