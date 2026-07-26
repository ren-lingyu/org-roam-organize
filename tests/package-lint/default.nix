{ pkgs, source, emacs } : (

  pkgs.runCommand "org-roam-organize-package-lint" {
    nativeBuildInputs = [
      emacs
    ];
  } (builtins.concatStringsSep "\n" [
    "export HOME=\"$TMPDIR/home\""
    "mkdir -p \"$HOME\""
    "mapfile -d \"\" elispFiles < <(find -L ${source} -type f -name \"*.el\" -print0)"
    "test \"\${#elispFiles[@]}\" -gt 0"
    "${pkgs.lib.getExe' emacs "emacs"} -Q --batch -L ${source} --load package-lint --funcall package-lint-batch-and-exit \"\${elispFiles[@]}\""
    "touch \"$out\""
  ])

)
