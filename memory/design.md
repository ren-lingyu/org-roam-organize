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

Providers return (:title TITLE :info INFO) or nil to cancel; missing/nil :provider uses the default. The core owns node construction, targets, templates and directory lifecycle. MOCs use their own internal provider with the same request protocol.

Templates separate properties and keywords. Native Org-roam ${field} and Org %<FORMAT> handle dynamic capture data; structured fixed values use narrow serialization, not a parallel interpolation language. Ordinary paths remain <directory>/${id}/${slug}.org; MOCs have fixed configured destinations.

A closure-backed, self-removing after-finalize hook now survives the capture call, schedules empty-directory cleanup when capture actually ends, and is removed on error. Do not assume the return from org-roam-capture- means capture has finalized.

## Testing architecture

The root flake composes a filtered source tree, packaged Emacs dependencies and test modules. Tests do not infer a parent-repository layout or depend on personal directories. ERT loads the installed package with real Org-roam; targeted function mocks remain useful without substituting a fake Org-roam object system.

The flake defines package build, ERT, package-lint and a development shell. Compilation warnings are errors. Nixpkgs is temporarily pinned to the revision containing the GNU ELPA Org hash-mismatch repair; the unstable URL remains commented for a later switch. That pin addresses a dependency fetch failure, not an application test failure.

## Citation model

One :cite registry record identifies managed literature file nodes. Citation synchronization computes their citing-node relationships from external cite refs and Org-roam citation rows, then reconciles #+ROAM_CITING_NODE: ID-link keywords under the configured Inbox. It visits all managed references so formerly cited nodes can lose stale entries.

MOC and citation synchronization share ID-link keyword parsing and reconciliation. Count distinct citing nodes rather than equating citation occurrence count with backlink count. Duplicate/malformed entries and ambiguous external keys produce diagnostics rather than arbitrary selection. Citation source keys are still external citekeys at this stage.
