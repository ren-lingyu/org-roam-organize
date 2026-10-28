# Org-roam Organize: 0.8.0 release preparation complete

## Current state

The user approved the release-preparation plan and committed the result as
`chore(release): prepare v0.8.0 metadata and documentation`. Read-only review
confirms the resulting commit matches the validated three-file candidate and
the ordinary worktree is clean.

The main source Version header and Nix version/melpaVersion are 0.8.0. README now
has an explicit 0.7.0-to-0.8.0 changes and migration section covering bibliography
opt-in, UUID title display and refresh limits, Citar activation, lisp installation
paths, named Nix outputs, and existing internal interface migration guidance.
No runtime behavior, minimum dependency declaration or lockfile was changed in
this preparation. Staging of exactly those three files was explicitly authorized;
the user performed the ordinary commit.

The earlier package/test migration and README alignment are complete. The source
fileset is rooted at lisp/, packages and tests use framework overlay discovery,
and the default Emacs package set is used. Only named org-roam-organize and emacs
package outputs are declared. See memory/design.md for the supported model and
memory/validation.md for detailed evidence and historical interpretation.

## Validation

With explicit user authorization, the release candidate passed
`timeout 120s nix flake check --no-write-lock-file` on x86_64-linux: four ERT suites,
package-lint and treefmt. Both named outputs built using nix build with --no-link,
--no-write-lock-file and --json. A batch installation smoke check in an isolated
HOME passed for 0.8.0 installed metadata and MELPA Package-Version header, nine
modules resolved inside the built package, eleven public commands, autoload file
presence, and loading without enabling the mode or forcing optional Citar.

The default Emacs was 31.1. No minimum-version, other-system or straight-install
runtime verification is claimed. Source header/Nix versions agree, README Elisp
blocks remain delimiter-balanced, and git diff --check passed. The committed
three-file change was inspected and matches this candidate. The checkpoint's
project parent identifies the exact committed release-preparation state inspected
after HEAD moved. Temporary installation scripts and build output JSON remain
under ignored project tmp/; future resumption does not depend on these files.

## Backlog and boundary

The requested version, README and validation preparation is complete. No v0.8.0
tag points at the inspected commit. The agent did not create a tag, push, publish,
prepare a release draft, introduce CHANGELOG, or update dependencies.

At the end of preparation, discuss whether to introduce CHANGELOG as a separate
task. The user wants any first CHANGELOG to consider historical release notes,
not only 0.8.0. Its format, historical scope and writes are not yet authorized.
Actual release operations remain for the user. Do not describe preparation as a
published release or start historical changelog reconstruction automatically.

## Retained lint finding

The committed rx any-to-in workaround avoids package-lint treating rx syntax as
the ordinary function introduced in Emacs 31.1. Version 20260903.2119 has that
symbol entry; locally retained 20260619.1246 does not. The older source was not
conclusively tied to the former lock. No minimum Emacs version increase or compat
dependency was needed.
