# Org-roam Organize: Org release history committed

## Current state and continuation

The user committed the Org history migration, the treefmt exclusions, the strict
.org ignore whitelist and the BibLaTeX check-name clarification. The inspected
ordinary project worktree and index are clean. The checkpoint's project parent
identifies the exact committed snapshot reviewed for this handoff.

CHANGELOG.org now contains seven DONE historical versions (v0.1.0-v0.7.0) with
matching tag CUSTOM_ID values, UTC CLOSED records and local detailed-note links.
The user manually set these states and changed the development entry to NEXT
v0.8.0 with CUSTOM_ID v0.8.0. That entry has no CLOSED or release-date claim.
The earlier pending human-state-assignment task is complete.

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
instructions are in local detailed files. Details currently link back to root IDs;
these backlinks are an adopted navigation choice, not a skill requirement. The
user considered removing them but chose to retain them for now.

Use English and native Org syntax, omit empty categories and internal-only work,
and preserve meaningful category ordering. Headline-to-first-object spacing has
no blank line, all source block delimiters are lowercase, trailing spaces are
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
ert-citar -> ert-cite-citar and ert-biblatex -> ert-cite-biblatex. README and current
check overlays agree. User-facing history must not narrate release-note mistakes
or historical research; keep discrepancies in reports/memory. Hosted notes and
historical tagged trees were not rewritten.

## Tracking and verification

The committed .gitignore whitelist uses !/CHANGELOGS/*.org. treefmt excludes
CHANGELOG.org and CHANGELOGS/*.org. The user reported that omitting the existing
root changelog exclusion made nix flake check fail; that was the reason for the
separate fix(treefmt) commit. No fresh Nix check after that fix was run or claimed.

Static verification covered eight files, 18 local links, seven UTC CLOSED records,
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
