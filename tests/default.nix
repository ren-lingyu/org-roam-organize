{
  src,
  pkgs,
  llib,
  emacs,
}:
llib.tests.mkChecks {
  root = ./.;
  overlayFile = "test-overlay.nix";
  separator = "-";
  args = {
    inherit (pkgs)
      lib
      runCommand
      guile
      replaceVarsWith
      emacsPackages
      ;
    inherit src emacs;
    testSupport = import ./support;
  };
}
