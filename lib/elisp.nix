# Nix values to Emacs Lisp literals, and the variable forms built on top of
# them (`defvar`, `setq`, `setopt`).
#
# This is what lets a feature file write
#
#     setq = { my-font-size = 180; show-trailing-whitespace = true; };
#
# instead of hand-writing Elisp, so values that live in Nix (fonts, store
# paths, booleans from other modules) can be handed to Emacs.
{ lib }:

let
  inherit (lib)
    concatStringsSep
    isAttrs
    isBool
    isFloat
    isInt
    isList
    isPath
    isString
    mapAttrsToList
    ;

  # JSON string literals are valid Elisp string literals, so `builtins.toJSON'
  # does the escaping for us.
  string = builtins.toJSON;

  # A string that starts like Elisp code is inserted verbatim.  This is how you
  # pass symbols and quoted forms:
  #
  #     setq = { uniquify-buffer-name-style = "'post-forward"; };
  #     setq = { ediff-setup = "#'ediff-setup-windows-plain"; };
  #
  # A literal string that happens to start with one of these characters can be
  # protected with the `raw' escape hatch below.
  looksLikeElisp = value: lib.hasPrefix "'" value || lib.hasPrefix "#'" value || lib.hasPrefix "(" value;

  # Values of `defvar'/`setq'/`setopt' are Nix values; a set becomes an
  # alist, which is the shape most Elisp options take.
  toElispValue =
    value:
    if value == null then
      "nil"
    else if isBool value then
      (if value then "t" else "nil")
    else if isInt value || isFloat value then
      toString value
    else if isPath value || lib.isDerivation value then
      string (toString value)
    else if isString value then
      (if looksLikeElisp value then value else string value)
    else if isList value then
      "'(" + concatStringsSep " " (map toElispValue value) + ")"
    else if isAttrs value then
      (
        if value ? _elisp then
          value._elisp
        else
          "'("
          + concatStringsSep " " (
            mapAttrsToList (name: value: "(${string name} . ${toElispValue value})") value
          )
          + ")"
      )
    else
      throw "nix-emacs-home: cannot convert a value of type ${builtins.typeOf value} to Emacs Lisp";

  # (defvar NAME VALUE), (setq NAME VALUE), (setopt 'NAME VALUE).
  #
  # `setopt' is the one to use for `defcustom's: unlike `setq' it runs the
  # option's :set function.  Note the quote before the name, `setopt' takes
  # quoted symbols.
  defvarForm = name: value: "(defvar ${name} ${toElispValue value})";
  setqForm = name: value: "(setq ${name} ${toElispValue value})";
  setoptForm = name: value: "(setopt '${name} ${toElispValue value})";

  forms = form: attrs: concatStringsSep "\n" (mapAttrsToList form attrs);

  # Variable definitions, in the order they should hit Emacs: define first,
  # then assign plain variables, then user options.
  variables =
    { defvar ? { }, setq ? { }, setopt ? { } }:
    concatStringsSep "\n" (
      lib.filter (x: x != "") [
        (forms defvarForm defvar)
        (forms setqForm setq)
        (forms setoptForm setopt)
      ]
    );
in
{
  # Escape hatch for values `toElispValue' cannot express (property lists,
  # backquoted forms, ...).  Both of these insert the text unchanged:
  #
  #     { _elisp = "'(:foo 1 :bar 2)"; }
  #     (lib.emacs.raw "'(:foo 1 :bar 2)")
  raw = value: { _elisp = value; };

  toElisp = toElispValue;

  defvar = defvarForm;
  setq = setqForm;
  setopt = setoptForm;

  inherit
    forms
    variables
    ;

  defvars = forms defvarForm;
  setqs = forms setqForm;
  setopts = forms setoptForm;
}
