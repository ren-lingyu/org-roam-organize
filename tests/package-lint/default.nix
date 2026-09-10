{ pkgs, source, mkEmacs } : let

  emacs = mkEmacs (ps_ : [
    ps_.package-lint
  ]);

in (

  pkgs.runCommand "org-roam-organize-package-lint" {
    nativeBuildInputs = [
      emacs
      pkgs.guile
    ];
  } (pkgs.replaceVarsWith {
    src = ./run.scm;
    isExecutable = true;
    replacements = {
      guile = pkgs.lib.getExe pkgs.guile;
      emacs = pkgs.lib.getExe' emacs "emacs";
      source = "${source}";
    };
  })

)
