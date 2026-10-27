{
  lib,
  runCommand,
  guile,
  replaceVarsWith,
  emacs,
  name,
  testFile,
}:
runCommand name
  {
    nativeBuildInputs = [
      emacs
      guile
    ];
  }
  (replaceVarsWith {
    src = ./ert-run.scm;
    isExecutable = true;
    replacements = {
      guile = lib.getExe guile;
      emacs = lib.getExe' emacs "emacs";
      testFile = "${testFile}";
    };
  })
