{

  description = "Emacs package: org-roam-organize";

  inputs = {
    nixpkgs = {
      url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&shallow=1";
      # url = "github:NixOS/nixpkgs/94a9730314351929f8e4ca5dd28d461f87e7ba76";
    };
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts.git?ref=refs/heads/main&shallow=1";
    };
  };

  outputs = { self, ... }@inputs : inputs.flake-parts.lib.mkFlake { inherit inputs; } {

    systems = inputs.nixpkgs.lib.systems.flakeExposed;

    perSystem = { config, pkgs, ... } : let

      source = pkgs.lib.fileset.toSource {
        root = ./.;
        fileset = pkgs.lib.fileset.unions [
          ./org-roam-organize.el
          ./org-roam-organize-citar.el
          ./README.org
          ./LICENSE
        ];
      };

      emacsPackages = pkgs.emacsPackagesFor pkgs.emacs31;

      mkEmacs = selectPackages : emacsPackages.emacsWithPackages (ps_ : (builtins.concatLists [
        (selectPackages ps_)
        [ config.packages.default ]
      ]));

    in {

      packages = {
        default = emacsPackages.trivialBuild {
          pname = "org-roam-organize";
          version = "0.6.0";
          src = source;
          packageRequires = [
            emacsPackages.org
            emacsPackages.org-roam
          ];
          turnCompilationWarningToError = true;
        };
      };

      checks = import ./tests {
        inherit pkgs source mkEmacs;
      };

      devShells = {
        default = pkgs.mkShell {
          packages = [
            (mkEmacs (ps_ : [
              ps_.package-lint
            ]))
          ];
        };
      };

    };

  };

}
