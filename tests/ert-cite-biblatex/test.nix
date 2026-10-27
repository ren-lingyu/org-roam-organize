{
  lib,
  runCommand,
  guile,
  replaceVarsWith,
  emacs,
  testSupport,
}:
testSupport.mkErtCheck {
  inherit
    lib
    runCommand
    guile
    replaceVarsWith
    ;
  inherit emacs;
  name = "org-roam-organize-cite-biblatex-ert";
  testFile = ./ert.el;
}
