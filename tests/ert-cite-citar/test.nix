{
  lib,
  runCommand,
  guile,
  replaceVarsWith,
  emacsPackages,
  testSupport,
}:
testSupport.mkErtCheck {
  inherit
    lib
    runCommand
    guile
    replaceVarsWith
    ;
  emacs = emacsPackages.emacsWithPackages (ps: [
    ps.org-roam-organize
    ps.citar
  ]);
  name = "org-roam-organize-cite-citar-ert";
  testFile = ./ert.el;
}
