{
  # First feature in the generated init file.
  order = -10000;

  setq = {
    ring-bell-function = "'ignore";
    confirm-nonexistent-file-or-buffer = false;
    scroll-conservatively = 101;
  };

  elisp = ''
    (fset 'yes-or-no-p 'y-or-n-p)
  '';
}
