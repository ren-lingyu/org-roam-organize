{
  lib,
  runCommand,
  guile,
  replaceVarsWith,
  src,
  emacsPackages,
}:
let
  emacs = emacsPackages.emacsWithPackages (ps: [
    ps.org-roam-organize
    ps.package-lint
  ]);
in
runCommand "org-roam-organize-package-lint"
  {
    nativeBuildInputs = [
      emacs
      guile
    ];
  }
  (replaceVarsWith {
    src = ./run.scm;
    isExecutable = true;
    replacements = {
      guile = lib.getExe guile;
      emacs = lib.getExe' emacs "emacs";
      source = toString src;
    };
  })
