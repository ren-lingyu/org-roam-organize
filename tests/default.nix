{ pkgs, source, mkEmacs } :

(import ./ert {
  inherit pkgs mkEmacs;
}) // {

  package-lint = import ./package-lint {
    inherit pkgs source mkEmacs;
    packageMainFile = "${source}/org-roam-organize.el";
  };

}
