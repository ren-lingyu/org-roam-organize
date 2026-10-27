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
  name = "org-roam-organize-ert";
  testFile = ./ert.el;
}
