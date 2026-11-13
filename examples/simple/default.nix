# An Emacs configuration using nix-emacs-home, built by `nix build .#emacs`.
{ pkgs, ... }:
{
  home.username = "example";
  home.homeDirectory = if pkgs.stdenv.hostPlatform.isDarwin then "/Users/example" else "/home/example";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  # Anything in `_module.args' is handed to feature files that ask for it, which
  # is how configuration owned by someone else (a host's font choice, another
  # module's enable flag) reaches a feature.
  _module.args.exampleFonts = {
    mono = "Iosevka";
    proportional = "DejaVu Sans";
  };

  emacs = {
    enable = true;
    package = pkgs.emacs;

    featureDirs = [ ./features ];

    earlySetq = {
      inhibit-startup-screen = true;
      make-backup-files = false;
    };

    # Features do not have to live in a file, and a feature defined in a file
    # can be extended here: list options such as `packages' merge.
    features.version-control.packages = [ pkgs.gh ];
    features.minor-mode-demo.elisp = ''
      (example-minor-mode 1)
    '';
    features.modal-editing.enable = false;
  };
}
