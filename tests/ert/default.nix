{ pkgs, mkEmacs } :

let

  mkErtCheck = {
    name,
    testFile,
    extraPackages ? (_ : [ ]),
  } : let

    emacs = mkEmacs extraPackages;

  in pkgs.runCommand name {
    nativeBuildInputs = [
      emacs
    ];
  } (builtins.concatStringsSep "\n" [
    "export HOME=\"$TMPDIR/home\""
    "mkdir -p \"$HOME\""
    "${pkgs.lib.getExe' emacs "emacs"} -Q --batch --load ${testFile} --funcall ert-run-tests-batch-and-exit"
    "touch \"$out\""
  ]);

in {

  ert = mkErtCheck {
    name = "org-roam-organize-ert";
    testFile = ./ert.el;
  };

  ert-citar = mkErtCheck {
    name = "org-roam-organize-citar-ert";
    testFile = ./citar.el;
    extraPackages = ps_ : [
      ps_.citar
    ];
  };

}
