{ pkgs, emacs } : (

  pkgs.runCommand "org-roam-organize-ert" {
    nativeBuildInputs = [
      emacs
    ];
  } (builtins.concatStringsSep "\n" [
    "export HOME=\"$TMPDIR/home\""
    "mkdir -p \"$HOME\""
    "${pkgs.lib.getExe' emacs "emacs"} -Q --batch --load ${./ert.el} --funcall ert-run-tests-batch-and-exit"
    "touch \"$out\""
  ])

)
