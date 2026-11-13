{
  # A package that is not in nixpkgs, defined next to the feature that uses it.
  overlay = import ./_local-packages.nix;

  epkgs = epkgs: [ epkgs.example-minor ];
}
