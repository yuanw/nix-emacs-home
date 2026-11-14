# Turn a directory of feature files into the value of `emacs.features'.
#
# A feature file is any `*.nix' file in a feature directory whose name does not
# start with `_'; the feature name is the file name without `.nix'.  Files
# starting with `_' are left alone so shared helpers can sit next to features.
#
# A feature file contains only feature options (`epkgs', `elisp', `packages',
# ...), optionally as a function of the module arguments it asks for.  A file
# whose sibling `<name>.el' exists uses it as `elispFile'.  Anything that is not
# a feature belongs in Home Manager's `imports', not in a feature directory.
{ lib }:

let
  inherit (lib)
    attrNames
    baseNameOf
    elem
    filterAttrs
    functionArgs
    intersectAttrs
    isAttrs
    isFunction
    mapAttrs
    removeSuffix
    subtractLists
    ;

  # Keep in sync with the options of `featureModule' in ../modules/emacs.nix.
  featureOptionNames = [
    "defvar"
    "elisp"
    "elispFile"
    "enable"
    "epkgs"
    "order"
    "overlay"
    "packages"
    "requireEpkgs"
    "setq"
    "setopt"
  ];

  # Every *.nix file in DIR that is not a `_'-prefixed helper, sorted by name so
  # that features sharing an `order' merge predictably.
  collect =
    dir:
    map (name: dir + "/${name}") (
      attrNames (
        filterAttrs (
          name: type: type == "regular" && lib.hasSuffix ".nix" name && !lib.hasPrefix "_" name
        ) (builtins.readDir dir)
      )
    );

  featureName = path: removeSuffix ".nix" (baseNameOf path);

  elispSibling = path: (removeSuffix ".nix" (toString path)) + ".el";

  # Feature files are called with the arguments they ask for, so that
  #
  #     { pkgs, myConfig, ... }: { epkgs = ...; }
  #     { thisFeature }: { options, ... }: { order = thisFeature; }
  #
  # both work, and the result — plain data — can be handed to the feature
  # submodule type (handing it a function would give `pkgs' the submodule's
  # meaning).
  applyArgs =
    path: module: args:
    let
      apply =
        module:
        let
          wanted = mapAttrs (_name: _hasDefault: true) (functionArgs module);
          missing = subtractLists (attrNames args) (attrNames wanted);
        in
        if missing != [ ] then
          throw ''
            nix-emacs-home: the feature file ${path} takes the argument(s) ${lib.concatStringsSep ", " missing}, which are not available.
            Available: ${lib.concatStringsSep ", " (attrNames args)}.
          ''
        else
          module (intersectAttrs wanted args);
      # At most two rounds, for the curried `{ thisFeature }: { pkgs, ... }: ...'
      # form; more than that is a file that does not return a feature.
      go =
        n: module:
        if !isFunction module then
          module
        else if n >= 2 then
          throw "nix-emacs-home: the feature file ${path} takes more than two rounds of arguments"
        else
          go (n + 1) (apply module);
    in
    go 0 module;

  # A feature file may only contain feature options.  Anything else is reported
  # as what it probably is: a typo, or a Home Manager module that belongs in
  # `imports' rather than in a feature directory.
  checkFile =
    path: module:
    let
      keys = attrNames module;
      unknownKeys = lib.filter (name: !elem name featureOptionNames) keys;
    in
    if !isAttrs module then
      throw "nix-emacs-home: the feature file ${path} must be an attribute set or a function returning one"
    else if keys == [ ] || unknownKeys == [ ] then
      module
    else if
      (lib.filter (
        name:
        elem name [
          "options"
          "config"
          "imports"
        ]
      ) keys) != [ ]
      || module ? home
      || module ? systemd
      || module ? xdg
    then
      throw ''
        nix-emacs-home: the file ${path} is a Home Manager module, not a feature.
        Unknown attributes: ${lib.concatStringsSep ", " unknownKeys}.
        A feature file contains only ${lib.concatStringsSep ", " featureOptionNames};
        move this file out of the feature directory and add it to your Home Manager imports.
      ''
    else
      throw ''
        nix-emacs-home: the feature file ${path} has unknown attributes: ${lib.concatStringsSep ", " unknownKeys}.
        A feature file contains only ${lib.concatStringsSep ", " featureOptionNames}.
      '';

  # One feature: named after the file, with the sibling `.el' as its default
  # `elispFile' (an explicit `elispFile' in the file wins).
  applyFile =
    args: path:
    let
      name = featureName path;
      module = checkFile path (applyArgs path (import path) (args // { thisFeature = name; }));
      sibling = elispSibling path;
    in
    {
      inherit name;
      value =
        lib.optionalAttrs (builtins.pathExists sibling) {
          elispFile = lib.mkDefault sibling;
        }
        // module;
    };

  # The features of the given files, as the value of `emacs.features'.
  #
  # Feature files become option definitions rather than imported modules:
  # applying a file needs the module arguments, and `imports' is forced before
  # the module arguments exist.  The result must stay behind a thunk in the
  # config: applying a file reads `config', and a module that reads `config'
  # while the spine of its own config is being built cannot terminate.
  collectFeatures =
    args: paths:
    let
      entries = map (applyFile args) paths;
    in
    if
      builtins.length entries != builtins.length (builtins.attrNames (builtins.listToAttrs entries))
    then
      throw "nix-emacs-home: two feature files have the same name: ${
        lib.concatStringsSep ", " (map (e: e.name) entries)
      }"
    else
      builtins.listToAttrs entries;

in
{
  inherit collect featureOptionNames collectFeatures;
}
