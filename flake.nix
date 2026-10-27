{

  description = "Emacs package: org-roam-organize";

  inputs = {
    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&shallow=1";
    };
    personal-nixpkgs = {
      url = "git+https://github.com/ren-lingyu/nixpkgs.git?ref=refs/heads/main&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    inputs.personal-nixpkgs.lib.mkFlake inputs.nixpkgs
      ({ lib }: {
        inherit inputs;
        moduleLocation = __curPos.file;
      })
      {

        systems = inputs.nixpkgs.lib.systems.flakeExposed;

        perSystem =
          { config, pkgs, ... }:
          let

            source = pkgs.lib.fileset.toSource {
              root = ./lisp;
              fileset = pkgs.lib.fileset.unions [ ./lisp ];
            };

            emacsPackages = pkgs.emacsPackagesFor pkgs.emacs31;

            mkEmacs =
              selectPackages:
              emacsPackages.emacsWithPackages (
                ps_:
                (builtins.concatLists [
                  (selectPackages ps_)
                  [ config.packages.default ]
                ])
              );

          in
          {

            packages = {
              default = emacsPackages.trivialBuild {
                pname = "org-roam-organize";
                version = "0.7.0";
                src = source;
                packageRequires = [
                  emacsPackages.org
                  emacsPackages.org-roam
                ];
                turnCompilationWarningToError = true;
              };
            };

            checks = import ./tests { inherit pkgs source mkEmacs; };

            devShells = {
              default = pkgs.mkShell {
                packages = [
                  (mkEmacs (
                    ps_: with ps_; [
                      package-lint
                      citar
                    ]
                  ))
                ];
              };
            };

            treefmt = {
              flakeCheck = true;
              settings.excludes = [
                ".gitignore"
                "LICENSE"
                "README.org"
                "flake.lock"
              ];
            };

          };

      };

}
