{ pkgs, ... }:
{
  # Turned off from ../default.nix, so neither the package nor the Elisp below
  # reaches the build.
  epkgs = epkgs: [ epkgs.which-key ];
  packages = [ pkgs.ripgrep ];

  elisp = ''
    (which-key-mode 1)
  '';
}
