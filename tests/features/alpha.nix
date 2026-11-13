{ thisFeature, pkgs, ... }:
let
  # Files starting with `_' are not features, so they can hold shared code.
  helper = import ./_helper.nix;
in
{
  order = 10;

  epkgs = epkgs: [ epkgs.undo-tree ];

  # ../config.nix adds pkgs.git to this list.
  packages = [ pkgs.jq ];

  defvar = {
    test-alpha-var = thisFeature;
    test-alpha-documented = {
      value = 1;
      doc = "A variable with a docstring.";
    };
  };
  setq = {
    test-alpha-list = [ 1 "two" true ];
    test-helper = helper.helper-value;
  };
  setopt = {
    test-alpha-option = true;
    test-alpha-symbol = "'some-symbol";
  };

  elisp = "(message \"alpha elisp\")";
}
