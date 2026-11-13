{ pkgs, ... }:
{
  # Emacs Lisp packages come from the Emacs package set...
  epkgs = epkgs: [ epkgs.undo-tree ];

  # ...and the external programs the modes shell out to are ordinary Home
  # Manager packages.  (`pkgs.gh' is added to this list from ../default.nix.)
  packages = [ pkgs.git ];

  # A `defcustom' of the package above, set with a Nix value.
  setopt = {
    undo-tree-height = 90;
    undo-tree-visualizer-diff = false;
  };
}
