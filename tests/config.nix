{ pkgs, ... }:
{
  home.username = "test";
  home.homeDirectory = "/home/test";
  home.stateVersion = "25.11";
  programs.home-manager.enable = true;

  # Feature files read these, see features/reads-args.nix.
  _module.args.testInjected = "injected-value";

  emacs = {
    enable = true;
    package = pkgs.emacs;
    featureDirs = [ ./features ];

    earlyDefvar.test-early-var = 42;
    earlyElisp = "(message \"early from nix\")";

    features = {
      # A feature file switched off from the outside.
      gamma.enable = false;
      # A list option merges with the one in the feature file.
      alpha.packages = [ pkgs.git ];
      # A feature that exists nowhere but here.
      inline = {
        order = 9999;
        elisp = "(message \"inline feature\")";
      };
    };
  };
}
