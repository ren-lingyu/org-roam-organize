{ pkgs, mkEmacs } : let

  mkErtCheck = {
    name,
    testFile,
    extraPackages ? (_ : [ ]),
  } : let
    emacs = mkEmacs extraPackages;
  in pkgs.runCommand name {
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
      testFile = "${testFile}";
    };
  });

in {

  ert = mkErtCheck {
    name = "org-roam-organize-ert";
    testFile = ./ert.el;
  };

  ert-cite-citar = mkErtCheck {
    name = "org-roam-organize-cite-citar-ert";
    testFile = ./cite-citar.el;
    extraPackages = ps_ : [
      ps_.citar
    ];
  };

  ert-cite-biblatex = mkErtCheck {
    name = "org-roam-organize-cite-biblatex-ert";
    testFile = ./cite-biblatex.el;
  };

  ert-cite-display = mkErtCheck {
    name = "org-roam-organize-cite-display-ert";
    testFile = ./cite-display.el;
  };

}
