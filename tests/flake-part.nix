# Eval tests: build a Home Manager configuration with the module and the
# features in ./features, then check what came out.  The Emacs Lisp that the
# module generates is a plain string option, so this needs no Emacs build;
# `nix flake check' also builds ../examples/simple through packages.emacs, which
# is what proves the package/overlay wiring.
{ inputs, lib, ... }:

{ perSystem = { pkgs, ... }: let
  inherit (lib.strings) hasInfix;
  inherit (lib) concatStringsSep;

  evalConfig = modules: (inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [ inputs.self.hmModules.default ] ++ modules;
  }).config;

  cfg = evalConfig [ ./config.nix ];
  init = cfg.emacs.initContent;
  early = cfg.emacs.earlyContent;

  featureLib = import ../lib/features.nix { inherit lib; };

  # A feature file that mixes feature options with Home Manager options is a
  # mistake, and must be reported as one.  The check is lazy, so force the
  # feature values.
  mixedIsRejected = !(builtins.tryEval (
    lib.deepSeq (featureLib.collectFeatures { } [ ./bad-features/mixed.nix ]) true
  )).success;

  expect = name: condition: {
    inherit name condition;
    failed = !condition;
  };

  # The `;;;; name' headings, in the order they appear in the init file.
  headingOrder = map (lib.removePrefix ";;;; ") (
    lib.filter (line: lib.hasPrefix ";;;; " line) (lib.splitString "\n" init)
  );
  headingPosition = builtins.listToAttrs (
    lib.imap0 (i: heading: {
      name = heading;
      value = i;
    }) headingOrder
  );
  # Length of the part of the init file before the first occurrence of a
  # substring — a cheap position for comparing two pieces of Elisp.
  prefixLength = needle: builtins.stringLength (builtins.head (lib.splitString needle init));
  elispComesBefore = a: b: prefixLength a < prefixLength b;
  comesBefore = a: b: headingPosition.${a} < headingPosition.${b};

  expectations = [
    # Feature files, imported from the directory.
    (expect "feature from file" (cfg.emacs.features ? alpha))
    (expect "underscore file is not a feature" (!cfg.emacs.features ? _helper))
    (expect "feature elisp" (hasInfix "(message \"alpha elisp\")" init))
    (expect "sibling .el file" (hasInfix "beta from file" init))
    (expect "elisp after sibling file" (elispComesBefore "beta from file" "beta inline"))
    (expect "feature heading" (hasInfix ";;;; alpha" init))

    # Elisp declared in Nix rather than in a file.
    (expect "inline feature" (hasInfix "(message \"inline feature\")" init))

    # Nix values as Emacs variables.
    (expect "defvar with feature name" (hasInfix "(defvar test-alpha-var \"alpha\")" init))
    (expect "setq list" (hasInfix "(setq test-alpha-list '(1 \"two\" t))" init))
    (expect "setopt runs :set" (hasInfix "(setopt 'test-alpha-option t)" init))
    (expect "setopt symbol" (hasInfix "(setopt 'test-alpha-symbol 'some-symbol)" init))
    (expect "value from _module.args" (hasInfix "(setq test-injected \"injected-value\")" init))
    (expect "value from a helper file" (hasInfix "(setq test-helper \"from the helper\")" init))

    # Order.
    (expect "order puts the prelude first" (comesBefore "prelude" "alpha"))
    (expect "order puts the inline feature last" (comesBefore "alpha" "inline"))

    # Disabled features contribute nothing.
    (expect "disabled feature has no elisp" (!hasInfix "gamma must not appear" init))
    (expect "disabled feature has no heading" (!hasInfix ";;;; gamma" init))

    # Home Manager packages from features, merged with packages added to the
    # same feature from outside.
    (expect "feature package" (lib.any (p: p == pkgs.jq) cfg.home.packages))
    (expect "package added to a feature file" (lib.any (p: p == pkgs.git) cfg.home.packages))
    (expect "disabled feature package absent" (!lib.any (p: p == pkgs.ripgrep) cfg.home.packages))
    (expect "emacs is installed" (lib.any (p: p == cfg.emacs.finalPackage) cfg.home.packages))

    # A Home Manager module in a feature directory is rejected, see
    # bad-features/mixed.nix below.

    # Early init.
    (expect "early defvar" (hasInfix "(defvar test-early-var 42)" early))
    (expect "early elisp" (hasInfix "(message \"early from nix\")" early))
    (expect "early init file is written" (cfg.home.file ? ".emacs.d/early-init.el"))

    # Guard rails.
    (expect "mixed feature file is rejected" mixedIsRejected)
  ];

  failures = map (e: e.name) (builtins.filter (e: e.failed) expectations);

  assertion = lib.throwIf (failures != [ ]) ''
    nix-emacs-home: ${toString (builtins.length expectations)} checks were expected to pass, these failed:
      ${concatStringsSep "\n      " failures}
  '' "all checks passed";
in
{
  checks.tests = pkgs.runCommand "nix-emacs-home-tests"
    {
      # Forcing this string is what runs the checks above.
      result = assertion;
    }
    ''
      test -s ${cfg.emacs.initFile}
      echo '${assertion}' > $out
    '';
};
}
