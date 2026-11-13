# Turn a directory of feature files into Home Manager modules.
#
# A feature file is any `*.nix' file in a feature directory whose name does not
# start with `_'; the feature name is the file name without `.nix'.  Files
# starting with `_' are left alone so shared helpers can sit next to features.
#
# Two shapes are accepted, see the README:
#
#   * a feature file, whose attributes are all feature options (`epkgs',
#     `elisp', `packages', ...) — it becomes `emacs.features.<name>';
#   * a plain Home Manager module, imported unchanged, so a feature file can
#     also reach for `home.file' or declare its own options.
#
# A feature file whose sibling `<name>.el' exists uses it as `elispFile'.
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
  #
  # works, and the result — plain data — can be handed to the feature submodule
  # type (handing it a function would give `pkgs' the submodule's meaning).
  applyArgs =
    path: module: args:
    if !isFunction module then
      module
    else
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

  # "feature" when every attribute is a feature option, "plain" when the file
  # defines Home Manager options instead.  Mixing the two in one file is almost
  # always a typo, so it is an error rather than a silent "plain module" full of
  # unknown options.
  classify = path: module:
    let
      keys = attrNames module;
      featureKeys = lib.filter (name: elem name featureOptionNames) keys;
      otherKeys = lib.filter (name: !elem name featureOptionNames) keys;
    in
    if !isAttrs module then
      throw "nix-emacs-home: the feature file ${path} must be an attribute set or a function returning one"
    else if module ? options || module ? config || module ? imports then
      throw ''
        nix-emacs-home: the file ${path} is a Home Manager module, not a feature: it declares ${
          lib.concatStringsSep ", " (
            lib.filter (name: elem name [ "options" "config" "imports" ]) keys
          )
        }.
        Add it to your Home Manager imports instead of putting it in a feature directory.
      ''
    else if featureKeys == [ ] then
      "plain"
    else if otherKeys == [ ] || keys == [ ] then
      "feature"
    else
      throw "nix-emacs-home: the feature file ${path} mixes feature options (${
        lib.concatStringsSep ", " featureKeys
      }) with Home Manager options (${lib.concatStringsSep ", " otherKeys})";

  applyFile = args: path:
    let
      name = featureName path;
      module = applyArgs path (import path) (args // { thisFeature = name; });
      sibling = elispSibling path;
      # Explicit `elispFile' in the file wins over the sibling.
      defaultElispFile = lib.optionalAttrs (builtins.pathExists sibling) {
        elispFile = lib.mkDefault sibling;
      };
      kind = classify path module;
    in
    if kind == "plain" && module ? emacs then
      throw ''
        nix-emacs-home: the file ${path} is a Home Manager module that defines `emacs' options.
        A plain module in a feature directory may define anything but `emacs' options;
        add this file to your Home Manager imports instead.
      ''
    else
      {
        inherit
          kind
          name
          path
        ;
        module = if kind == "feature" then defaultElispFile // module else module;
      };

  # Feature files become option definitions, not imported modules: applying a
  # feature file needs the module arguments, and `imports' is forced before the
  # module arguments exist.
  #
  # Feature definitions and plain-module definitions come out separately so the
  # caller can keep the spine of `config.emacs' lazy -- asking for any `emacs.*'
  # option must not force the feature files, or the module that reads its own
  # options would not terminate.
  collectDefinitions = args: paths:
    let
      entries = map (applyFile args) paths;
      featureEntries = lib.filter (e: e.kind == "feature") entries;
      features = lib.listToAttrs (
        map (e: { inherit (e) name; value = e.module; }) featureEntries
      );
      plainModules = map (e: e.module) (lib.filter (e: e.kind == "plain") entries);
    in
    if builtins.length featureEntries != builtins.attrLength features then
      throw "nix-emacs-home: two feature files have the same name (features: ${
        lib.concatStringsSep ", " (map (e: e.name) featureEntries)
      })"
    else
      {
        inherit
          features
          plainModules
        ;
      };

in
{
  inherit collect featureOptionNames collectDefinitions;
}
