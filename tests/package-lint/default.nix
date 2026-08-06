{ pkgs, source, mkEmacs, packageMainFile } : let

  emacs = mkEmacs (ps_ : [
    ps_.package-lint
  ]);

in (

  pkgs.runCommand "org-roam-organize-package-lint" {
    nativeBuildInputs = [
      emacs
    ];
  } (builtins.concatStringsSep "\n" [
    "export HOME=\"$TMPDIR/home\""
    "mkdir -p \"$HOME\""
    "${pkgs.lib.getExe' emacs "emacs"} -Q --batch -L ${source} --load package-lint --funcall package-lint-batch-and-exit ${packageMainFile}"
    "touch \"$out\""
  ])

)
