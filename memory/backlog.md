# Backlog

## Deferred: Package test organization and Nix integration

Status: deferred, non-blocking. Does not block 0.8.0 release preparation or release.
Resume only after an explicit user decision to reopen it. No deadline or target
version is chosen. The user ultimately decided to shelve the refactor/migration;
prior suggestions are discussion material, not approved architecture or tasks.

### Motivation and preferred direction

The user prefers the separation found in Cabal-based Haskell projects: the package
itself declares sources/test suites and owns their execution interface; Nix provides
the environment and invokes tests without intruding into their implementation.
Elisp package metadata and ERT lack an equivalent generally unified project manifest.
A thin project-owned runner was proposed rather than a new elaborate framework.
Keep project test code in tests/ if revisited; test ownership does not require moving
Elisp tests into pkgs/. Nix packaging/test derivations can remain thin adapters.

The user initially contemplated a single coherent migration commit and manually
changed the 0.8.0 headline from NEXT to TODO, then deferred the migration. Do not
interpret the TODO state as authorization to implement this backlog or restore NEXT.
Any future inclusion in a release is a separate scope decision.

### Discussion retained for future assessment

- Three suites are plausible checkPhase candidates: core ERT (90 tests), bundled
  BibLaTeX compatibility (7) and citation display (13). BibLaTeX tests generate/check
  LaTeX text without running TeX/Biber; display tests use batch buffers/font-lock
  and overlays without a desktop. These would retain their test cases while
  replacing independent derivations with build-local execution.
- Package-lint can also run in checkPhase, checking all package modules as source.
  Treat it as a test-only dependency, not packageRequires. An independently runnable
  development lint entry can reuse the same logic if desired. Keeping the current
  separate lint check remains valid while the migration is deferred.
- Optional Citar ERT (48 tests) is a plausible passthru.tests candidate: it actually
  loads Citar and includes temporary Org-roam SQLite database integration. This
  separation keeps optional integration out of default package build validation.
- Installed-artifact checks could later cover module inventory, autoloads, metadata,
  load paths and absence of implicit Citar loading. Such new tests were discussed,
  not authorized. passthru.tests fits consumer-side tests; installCheckPhase is an
  alternative if installation checks must gate every package build.
- MELPA build/install/compilation can cover some redundant packaging/compilation
  checks. It does not replace ERT behavior assertions or package-lint. Inspect the
  actual builder before deleting any apparently duplicate smoke check.
- Keep treefmt as a repository-level flake check. Explicitly expose passthru test
  derivations through flake checks if they must run under nix flake check; merely
  defining passthru.tests does not automatically execute them in a package build.

### Implementation constraints if reopened

Current ERT runners load an already built org-roam-organize through Emacs wrappers;
the package-lint wrapper also includes the built package despite linting source.
Directly adding those existing derivations to this package's own check/build inputs
would create a cycle. Build-local checks need a dependency-only Emacs environment
and an explicit source load path. Preserve suite/process isolation for hooks, advice
and other global state unless deliberate verification supports combining processes.

The current src fileset contains lisp/ only. Supply tests separately without
accidentally widening the packaged MELPA inventory. Preserve isolated writable HOME,
temporary files/databases, failure propagation and test-only dependency boundaries.
Passthru tests must consume the actual package under test, including overridden
instances, not a fixed default sibling. Reconnect flake checks without losing or
unnecessarily duplicating coverage; review documented names/commands if changed.

The existing Guile runner mixes execution with Nix-substituted paths and an output
marker. A possible future split leaves those Nix concerns in the adapter and gives
the project-owned runner only loading/execution/exit-status responsibilities. The
choice of runner language, interface and directory layout is intentionally open.

### Evidence and reopening checklist

The discussion was based on read-only inspection of the package, flake checks,
shared runners and ERT fixtures. Official Nixpkgs guidance distinguished build-local
upstream tests from independent installed-package tests. Retrieval of the exact
locked Emacs builder through public web sources failed; precise melpaBuild phases,
hooks and load-path handling remain unverified. No test/build/evaluation or project
implementation was performed for this proposal; runtime cost was not measured.

If reopened, inspect the then-current locked builder and test topology first,
confirm scope and desired project-owned entry points with the user, then prepare a
concrete plan. Validate recursion freedom, source-versus-installed loading, optional
Citar isolation, test discovery, package contents and cross-system constraints.
Existing tests remain in force throughout the deferral. Future progress should be
recorded here without treating this item as a release gate.
