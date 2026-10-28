# Org-roam Organize: README aligned with committed package layout

## Backlog

Next phase: prepare the 0.8.0 release.

## Current state

The user requested a README audit against HEAD, authorized necessary README
edits and then explicitly authorized staging README.org. The user committed the
result as `docs(readme): align package outputs and configuration examples`.
Only README changed in that commit. An independent unstaged flake.nix change
narrows llib to the framework's tests/packages exports; it was excluded from
this HEAD-based audit and remains untouched. No implementation work is pending.

The root flake provides the lisp fileset through `specialArgs.src`, discovers
package overlays through `packages.mkOverlays`, exports the Emacs package overlay
and legacy package set, and exposes named library and Emacs wrapper packages.
The committed flake removes the explicit `packages.default` declaration. The package uses melpaBuild, v0.7.0, Org and Org-roam dependencies and
compilation warnings as errors. Copied TeXmacs metadata was corrected.

The user explicitly requested default `pkgs.emacs` / `pkgs.emacsPackages`, without
selecting Emacs 31 in the flake. The wrapper calls emacsPackagesFor on its injected
Emacs, matching the reference pattern. The development shell also includes lint
and Citar.

Tests use `tests.mkChecks` and five `test-overlay.nix` leaves with `test.nix`.
Core ERT remains in `tests/ert/`; citation suites have separate `ert-cite-*`
directories and `ert.el` files. `tests/support/` holds the shared ERT builder and
Guile runner. Package-lint keeps its runner and recursive Lisp discovery. Existing
check names and suite contents remain unchanged. README describes the layout and
selects `lisp/*.el` in its straight recipe. Treefmt checks remain enabled.

## Validation and continuation

The user authorized formatting and flake checks in a filtered copy under ignored
project `tmp/packaging-check/`, without changing the Git index. Nix formatting was
synchronized back; at that point all 38 relevant input files matched the validated
copy. The later committed candidate differs only in flake.nix: the user removed
the explicit default package output and restyled equivalent attribute sets.
`timeout 120s nix flake check --no-write-lock-file path:.` passed on x86_64-linux,
including package build, four ERT suites, package-lint and treefmt. Other systems
were omitted. `git diff --check` passes. Migrated ERT files and the Guile runner
were confirmed unchanged in content.

An initial attempt failed because toString on testFile lost Nix input dependency
context. Interpolating the test path fixed it; subsequent checks passed. The
formatter was run via the explicit formatter.x86_64-linux output with filesystem
walking, since Git walking ignores the validation copy. The copy remains in tmp.
During the package migration, no lock update, ordinary staging or ordinary
commit was performed by the agent. README staging in the later audit was
explicitly authorized; the user performed the ordinary commit.
After committing, the user supplied successful `nix flake check` output (exit 0)
on the final clean worktree, confirming the final flake on x86_64-linux. Its
package output lists only the named library and Emacs wrapper.

The subsequent README audit corrected the default-package claim, documented
explicit named-package builds and clarified that test suite directories own
check overlays. It fixed the missing closing parenthesis in the use-package
registry example and the default hook spelling to after-init. It documented the
exactly-one-MOC-record rule and changed the provider example to add a record to
an existing valid registry, preserving its MOC record.

All nine README Elisp blocks have balanced delimiters and all nine referenced
package functions exist at the inspected HEAD. The hook convention was checked
against the official use-package Hooks manual. These are static checks; no
examples, builds, tests or formatters were run for the documentation task.
The documentation correction is committed; no further task is specified.

## Baseline and retained finding

Read `memory/design.md` for supported behavior and `memory/validation.md` for
evidence limits. Earlier checkpoint project-parent associations describe their
own inspected baselines. The current checkpoint's project parent identifies the
committed README state inspected after HEAD moved. The earlier successful flake
check applies to the package migration state, not a new runtime validation of
the documentation examples.
The committed rx `any` to `in` workaround avoids package-lint treating rx syntax
as the ordinary function introduced in Emacs 31.1. Version 20260903.2119 has that
symbol entry; locally retained 20260619.1246 does not. The older source was not
conclusively tied to the former lock. No minimum Emacs version increase or compat
dependency was needed.
