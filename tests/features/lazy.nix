{
  # Its packages stay on the load path and their autoloads are loaded, but they
  # are not `(require)'d at startup, so their code costs nothing to start Emacs.
  requireEpkgs = false;

  epkgs = epkgs: [ epkgs.flycheck ];

  elisp = "(message \"lazy elisp\")";
}
