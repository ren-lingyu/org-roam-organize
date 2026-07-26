{

  description = "Organize Org-roam node references";

  inputs = {
    nixpkgs = {
      # url = "git+https://github.com/NixOS/nixpkgs.git?ref=refs/heads/nixpkgs-unstable&shallow=1";
      url = "github:NixOS/nixpkgs/94a9730314351929f8e4ca5dd28d461f87e7ba76";
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
          ./README.org
          ./LICENSE
        ];
      };

      emacsPackages = pkgs.emacsPackagesFor pkgs.emacs31;

      emacs = emacsPackages.emacsWithPackages (ps_ : (builtins.concatLists [
        (with ps_; [
          package-lint
        ])
        [ config.packages.default ]
      ]));

    in {

      packages = {
        default = emacsPackages.trivialBuild {
          pname = "org-roam-organize";
          version = "0.4.0";
          src = source;
          packageRequires = [
            emacsPackages.org
            emacsPackages.org-roam
          ];
          turnCompilationWarningToError = true;
        };
      };

      checks = import ./tests {
        inherit pkgs source emacs;
      };

      devShells = {
        default = pkgs.mkShell {
          packages = [
            emacs
          ];
        };
      };

    };

  };

}
