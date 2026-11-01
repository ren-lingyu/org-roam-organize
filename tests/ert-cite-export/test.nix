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
    emacs
    ;
  name = "org-roam-organize-cite-export-ert";
  testFile = ./ert.el;
}
