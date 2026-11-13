{
  description = "Declarative, modular Emacs configuration for Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-parts,
      home-manager,
      ...
    }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ ./tests/flake-part.nix ];

      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      flake = {
        # Add to `home-manager.sharedModules' (or to any Home Manager module
        # list) and configure the `emacs' namespace.
        hmModules.default = ./modules/emacs.nix;

        # The Nix-to-Elisp printer the `setq'/`setopt'/`defvar' options use,
        # for when a config needs a value this module does not expose.
        lib = import ./lib/elisp.nix { lib = nixpkgs.lib; };
      };

      perSystem =
        { pkgs, ... }:
        {
          # The Emacs package the example config builds; `nix build .#emacs'.
          packages.emacs =
            (home-manager.lib.homeManagerConfiguration {
              inherit pkgs;
              modules = [
                self.hmModules.default
                ./examples/simple
              ];
            }).config.emacs.finalPackage;
        };
    };
}
