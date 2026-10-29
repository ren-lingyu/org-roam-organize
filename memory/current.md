# Org-roam Organize: Historical CHANGELOG committed

## Current state

The user approved and committed the first English CHANGELOG.org as
`docs(changelog): backfill release history and unreleased changes`.
It covers published 0.1.0-0.7.0 plus an undated Unreleased section for changes
from v0.7.0 to the release-preparation HEAD. Only CHANGELOG.org and its explicit
.gitignore whitelist entry changed. The user authorized staging these exact
paths and performed the ordinary commit; the inspected worktree is clean.

The committed CHANGELOG blob matches the fully reviewed candidate. The user
only regrouped the ignore whitelist entry before committing; its semantics are
unchanged and the commit's whitespace check passes. The checkpoint project
parent identifies the exact committed documentation snapshot inspected after
HEAD moved. No additional implementation or documentation task is pending.

## Documentation policy and evidence

Use English and Org-native headings, lists, inline code and direct links.
Released version numbers link to the actual release pages. Each verified
publication date is written as YYYY-MM-DD (UTC), derived from published_at,
not tag creation or commit dates. Unreleased has no date and does not claim
0.8.0 has been published. Omit empty change categories and internal-only work.
Breaking entries describe affected interfaces and migration directions.

Adjacent released source trees, historical READMEs and interfaces are primary
change evidence; the seven published GitHub release notes provide supplementary
context and omission checks. Local and remote tag objects were confirmed equal.
The user explicitly wants an ordinary user-facing changelog, without statements
about problems in release notes or historical investigation. Keep evidence
conflicts and gaps in the review report or memory, not in changelog entries.

The separate review findings are that 0.4.0 release notes name the former MOC
command org-roam-organize-moc-update, while actual 0.3.0 source defines
org-roam-organize-update-mocs; the changelog uses the real interface. Brief
0.2.0 notes omit explicit details of the default-keymap removal and declared
Emacs minimum increase, both recovered from endpoint source. No predecessor
release was established for 0.1.0; its entry is a limited documented baseline,
not a claim that all features in that tree were newly introduced.

## Validation and limits

Static checks passed for eight release sections, seven dates and release URLs,
category ordering and nonempty categories, eleven links, and project identifiers
against their relevant old/new source endpoints. Historical README link paths
and the local README heading target exist. Git's whitelist permits CHANGELOG.org.
The new, nonempty file passed no-index whitespace checking by accepting expected
status 1 rather than treating every nonzero status as failure; ordinary tracked,
staged and committed whitespace checks also passed. No builds, tests, formatters
or automated Org rendering were run for this documentation task.

## Release preparation and continuation

The 0.8.0 source and Nix metadata and README upgrade guide were already committed.
Their checks and installed-package smoke verification passed on x86_64-linux
with default Emacs 31.1 as recorded in memory/validation.md. That evidence is
separate from this static changelog audit; no minimum-version, other-system or
straight runtime validation is claimed. See memory/design.md for supported
behavior. The historical CHANGELOG backlog is now complete. No tag, push,
published release, hosted-note edits, dependency refresh or README edit was
performed as part of this task. Actual release operations remain for the user.
