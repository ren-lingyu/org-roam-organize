# Org-roam Organize: Package and test migration

## Current state

The user authorized completing the in-progress `pkgs/` migration and normalizing
`tests/`, referencing sibling `org-texmacs`. Sources were already under `lisp/`.
The user committed the migration as `build(nix): migrate packages and checks to
framework overlays`. The inspected ordinary worktree is clean. The agent did not
stage or commit ordinary-project files.

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
No lock update, ordinary staging or ordinary commit was performed by the agent.
After committing, the user supplied successful `nix flake check` output (exit 0)
on the final clean worktree, confirming the final flake on x86_64-linux. Its
package output lists only the named library and Emacs wrapper. README still
claims a default package remains, which needs a later documentation correction. No ordinary-project fix is authorized by the checkpoint task.
No additional implementation task is specified.

## Baseline and retained finding

Read `memory/design.md` for supported behavior and `memory/validation.md` for
evidence limits. Earlier checkpoint project-parent associations describe their
own inspected baselines. The new project-parent association identifies the exact
committed snapshot inspected after HEAD moved. The user subsequently supplied
successful flake-check output for that final committed state; the earlier agent
check used the separately described working candidate.
The committed rx `any` to `in` workaround avoids package-lint treating rx syntax
as the ordinary function introduced in Emacs 31.1. Version 20260903.2119 has that
symbol entry; locally retained 20260619.1246 does not. The older source was not
conclusively tied to the former lock. No minimum Emacs version increase or compat
dependency was needed.
