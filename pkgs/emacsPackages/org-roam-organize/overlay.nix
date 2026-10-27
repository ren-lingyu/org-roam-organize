{ extraArgs }: final_: prev_: {
  org-roam-organize = final_.callPackage ./package.nix { inherit (extraArgs) src; };
}
