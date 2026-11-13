# A Home Manager module that configures Emacs from feature files.
#
# Design notes:
#
#   * Everything Emacs-related is collected in one pass and installed as a
#     single `emacs.pkgs.withPackages` package, so features can freely add
#     Emacs Lisp packages and overlays without each of them wrapping Emacs.
#   * Feature Elisp ends up in a generated `default.el`, shipped as a package
#     named `default`.  Emacs loads it like `init.el` (it has no init file of
#     its own), and because it is a package its byte-compilation happens at
#     build time, so broken config fails the build instead of Emacs startup.
#   * Early configuration is written to `early-init.el` in the home directory
#     rather than being packaged, because the `early-default.el` equivalent is
#     only available in very recent Emacsen.
{ config, lib, pkgs, options, ... }:

let
  inherit (lib)
    composeManyExtensions
    concatMap
    concatStringsSep
    getVal
    isFunction
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    mkOptionType
    mkPackageOption
    optional
    optionalAttrs
    optionalString
    trim
    types
    ;

  elisp = import ../lib/elisp.nix { inherit lib; };
  featureLib = import ../lib/features.nix { inherit lib; };

  cfg = config.emacs;

  # `epkgs: [ epkgs.magit ]' — merged by applying every definition to the
  # final Emacs package set.  Only "is it a function" is checked: probing the
  # result would have to call it with a fake package set.
  selectorFunction = mkOptionType {
    name = "selector function";
    description = "function taking the Emacs package set and returning a list of packages";
    check = isFunction;
    merge =
      _loc: defs: epkgs: concatMap (select: select epkgs) (map getVal defs);
  };

  overlayFunction = mkOptionType {
    name = "overlay function";
    description = "Emacs package overlay, final: prev: { }";
    check = isFunction;
    merge = _loc: defs: composeManyExtensions (map getVal defs);
  };

  variablesOption = description: mkOption {
    type = types.attrsOf types.anything;
    default = { };
    example = literalExpression ''
      {
        font-height = 180;
        frame-title-format = "'(\"%b\")";
      }
    '';
    inherit description;
  };

  featureModule = types.submodule (
    { name, ... }:
    {
      options = {
        name = mkOption {
          type = types.str;
          internal = true;
          readOnly = true;
          default = name;
          description = "Name of this Emacs feature.";
        };

        enable = mkEnableOption "the ${name} Emacs feature" // {
          default = true;
        };

        order = mkOption {
          type = types.ints.signed;
          default = 0;
          description = ''
            Position of this feature in the generated init file.  Smaller comes
            first; features with the same order are sorted by name.  Use a very
            small value (say -10000) for a prelude and a very large one for a
            postlude.
          '';
        };

        epkgs = mkOption {
          type = selectorFunction;
          default = _epkgs: [ ];
          defaultText = literalExpression "epkgs: [ ]";
          example = literalExpression "epkgs: [ epkgs.magit epkgs.forge ]";
          description = ''
            Emacs Lisp packages this feature needs, selected from the Emacs
            package set.  The set already includes every `overlay' of every
            enabled feature, so packages defined by this feature's own overlay
            can be selected here.
          '';
        };

        overlay = mkOption {
          type = overlayFunction;
          default = _final: _prev: { };
          defaultText = literalExpression "final: prev: { }";
          example = literalExpression ''
            final: _prev: {
              my-mode = final.trivialBuild {
                pname = "my-mode";
                version = "0.1";
                src = ./my-mode.el;
              };
            };
          '';
          description = ''
            Overlay for the Emacs package set, used for packages that are not
            in nixpkgs or for patching the ones that are.
          '';
        };

        packages = mkOption {
          type = types.listOf types.package;
          default = [ ];
          example = literalExpression "[ pkgs.ripgrep pkgs.git ]";
          description = ''
            Non-Emacs packages this feature needs, installed into the home
            environment.  This is where the external programs an Emacs mode
            shells out to belong, next to the mode that uses them.
          '';
        };

        elisp = mkOption {
          type = types.str;
          default = "";
          example = literalExpression ''"(magit-todos-mode 1)"'';
          description = ''
            Emacs Lisp configuration for this feature, written inline in Nix.
            Interpolating Nix values into it is how store paths and other
            build-time facts reach Emacs.

            Both this and `elispFile' may be set: the file comes first, then
            this.
          '';
        };

        elispFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = literalExpression "./magit.el";
          description = ''
            File with Emacs Lisp configuration for this feature.

            For a feature imported from `featuresDir' this defaults to the
            sibling `.el' file, which is why a feature usually consists of a
            small `.nix' file and, when it grows, a matching `.el' file.
          '';
        };

        defvar = variablesOption ''
          Variables to define with `defvar' before this feature's Elisp, with
          values coming from Nix.  Use this for variables your own Elisp reads,
          e.g. fonts or directories selected in Nix.
        '';

        setq = variablesOption ''
          Variables to assign with `setq' before this feature's Elisp.  Values
          are Nix values: null becomes nil, true becomes t, a set becomes an
          alist, and a string that starts like Elisp code (with a quote, a
          hash-quote or an open paren) is inserted verbatim, which is how you
          pass symbols and quoted forms.
        '';

        setopt = variablesOption ''
          User options (`defcustom's) to set with `setopt' before this
          feature's Elisp.  Unlike `setq' this runs the option's `:set'
          function, so use it for options defined by packages.
        '';
      };
    }
  );

  sortedEnabledFeatures = lib.sortOn (feature: {
    inherit (feature) order name;
  }) (lib.filter (feature: feature.enable) (lib.attrValues cfg.features));

  epkgsOf = scope: concatMap (feature: feature.epkgs scope) sortedEnabledFeatures;

  # The generated init file travels as a package called `default', which is
  # what makes Emacs load it (see the note at the top of this file).
  initOverlay =
    _final: _prev: {
      default = _final.trivialBuild {
        pname = "default";
        version = "0.1.0";
        src = cfg.initFile;
        packageRequires = epkgsOf _final;
        turnCompilationWarningToError = cfg.pedantic;
      };
    };

  emacsScope = cfg.package.pkgs.overrideScope (
    composeManyExtensions (
      [ cfg.overlay ]
      ++ map (feature: feature.overlay) sortedEnabledFeatures
      ++ [ initOverlay ]
    )
  );

  finalPackage =
    lib.throwIf (cfg.package ? explicitRequires && cfg.package ? deps)
      "nix-emacs-home: emacs.package must be an unwrapped Emacs such as pkgs.emacs or pkgs.emacs-git, not one already configured with withPackages"
      (
        emacsScope.withPackages (
          epkgs: (epkgsOf epkgs) ++ optional (cfg.initContent != "") epkgs.default
        )
      );

  # `;;;; name' headings make the generated file navigable with outline-minor-mode.
  featureElisp =
    feature:
    let
      fromFile = if feature.elispFile == null then "" else builtins.readFile feature.elispFile;
      body = trim (
        concatStringsSep "\n" (
          lib.filter (x: x != "") [
            (elisp.variables feature)
            fromFile
            feature.elisp
          ]
        )
      );
    in
    optionalString (body != "") ";;;; ${feature.name}\n\n${body}\n";

  initContent = lib.optionalString (sortedEnabledFeatures != [ ]) ''
    ;;; default.el --- Emacs configuration generated by nix-emacs-home  -*- lexical-binding: t; -*-

    ;; Version: 0.1.0
    ;; Keywords: local

    ;;; Commentary:

    ;; Generated by nix-emacs-home.  Edit the features, not this file.

    ;;; Code:

    ${concatStringsSep "\n" (map featureElisp sortedEnabledFeatures)}
    (provide 'default)

    ;;; default.el ends here
  '';

  earlyContent =
    let
      fromFile = if cfg.earlyElispFile == null then "" else builtins.readFile cfg.earlyElispFile;
      body = trim (
        concatStringsSep "\n" (
          lib.filter (x: x != "") [
            (elisp.variables {
              defvar = cfg.earlyDefvar;
              setq = cfg.earlySetq;
              setopt = cfg.earlySetopt;
            })
            fromFile
            cfg.earlyElisp
          ]
        )
      );
    in
    optionalString (body != "") ''
      ;;; early-init.el --- generated by nix-emacs-home  -*- lexical-binding: t; -*-

      ${body}

      ;;; early-init.el ends here
    '';

  # `programs.emacs' wraps Emacs itself and generates its own init file, which
  # would fight with the package built here.
  hmEmacsWarning = lib.optionals (options.programs.emacs or { } != { } && config.programs.emacs.enable) [
    ''
      nix-emacs-home: both `emacs.enable' and `programs.emacs.enable' are on.
      Disable `programs.emacs', it wraps Emacs a second time and writes its own
      init file.
    ''
  ];

  # Feature files are called with these, so they see the same arguments as any
  # other Home Manager module plus whatever `_module.args' provides -- that is
  # how configuration that lives outside this module reaches a feature.
  featureArgs = config._module.args // {
    inherit
      config
      lib
      options
      pkgs
      ;
  };

  # Feature files become option definitions here rather than imported modules:
  # reading a feature file needs the module arguments, and `imports' is forced
  # before those exist (a module cannot look at `config' in its `imports').
  featureDefinitions =
    featureLib.mkDefinitions featureArgs
      (concatMap featureLib.collect cfg.featureDirs);
in
{
  options.emacs = {
    enable = mkEnableOption "declarative Emacs configuration managed by nix-emacs-home";

    package = mkPackageOption pkgs "emacs" { default = [ "emacs" ]; };

    pedantic = mkEnableOption "turning Emacs Lisp byte-compilation warnings into errors";

    overlay = mkOption {
      type = overlayFunction;
      default = _final: _prev: { };
      defaultText = literalExpression "final: prev: { }";
      description = ''
        Overlay for the Emacs package set, applied before the overlays of the
        enabled features.  Put packages shared by several features here.
      '';
    };

    features = mkOption {
      type = types.attrsOf featureModule;
      default = { };
      example = literalExpression ''
        {
          magit = {
            epkgs = epkgs: [ epkgs.magit ];
            packages = [ pkgs.git ];
            setopt.magit-diff-visit-prefer-worktree = true;
          };
        }
      '';
      description = ''
        Emacs features.  Each one contributes Emacs Lisp packages, an overlay,
        non-Emacs packages, variables and Elisp configuration.

        Features declared here are merged with the ones imported from
        `featuresDir', so a host can disable or extend a feature file without
        touching it.
      '';
    };

    featureDirs = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = literalExpression "[ ./features ]";
      description = ''
        Directories of feature files to import.  Each `.nix' file that does not
        start with `_' becomes a feature named after the file; `_'-prefixed
        files are left alone so shared helpers can live in the same directory.

        A file whose attributes are all feature options becomes
        `emacs.features.<name>'.  Any other file is imported as a plain Home
        Manager module, which lets a feature file also write `home.file' or
        declare options of its own.
      '';
    };

    earlyElisp = mkOption {
      type = types.str;
      default = "";
      description = ''
        Emacs Lisp for `early-init.el', written inline in Nix.  Runs before the
        GUI is initialized: faces, frame parameters, garbage collection
        settings.
      '';
    };

    earlyElispFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "File with Emacs Lisp for `early-init.el', applied before `earlyElisp'.";
    };

    earlyDefvar = variablesOption "Variables to `defvar' in `early-init.el'.";
    earlySetq = variablesOption "Variables to `setq' in `early-init.el'.";
    earlySetopt = variablesOption "User options to `setopt' in `early-init.el'.";

    earlyInitFile = mkOption {
      type = types.nullOr types.str;
      default = ".emacs.d/early-init.el";
      description = ''
        Where to write `early-init.el', relative to the home directory and
        interpreted as a `home.file' target.  Set to `null' to write nothing and
        keep an early init file you manage yourself.
      '';
    };

    service = {
      enable = mkEnableOption "the Emacs service (a daemon other frames can attach to)";
    };

    initContent = mkOption {
      type = types.str;
      internal = true;
      readOnly = true;
      default = initContent;
      description = "Content of the generated init file.  Useful with `nix repl'.";
    };

    initFile = mkOption {
      type = types.package;
      internal = true;
      readOnly = true;
      default = pkgs.writeText "default.el" cfg.initContent;
      defaultText = literalExpression "generated from initContent";
      description = "The generated init file.";
    };

    earlyContent = mkOption {
      type = types.str;
      internal = true;
      readOnly = true;
      default = earlyContent;
      description = "Content of the generated `early-init.el'.";
    };

    finalPackage = mkOption {
      type = types.package;
      readOnly = true;
      default = finalPackage;
      defaultText = literalExpression "the Emacs package built from the enabled features";
      description = ''
        The configured Emacs.  Installed automatically; read it from elsewhere
        when something needs the store path, e.g. an `EDITOR' wrapper or a
        launchd agent.
      '';
    };
  };

  config = mkIf cfg.enable (lib.mkMerge (
    [
      {
        assertions = [
          {
            assertion = cfg.package ? pkgs;
            message = "nix-emacs-home: emacs.package must be an unwrapped Emacs (it needs a .pkgs attribute)";
          }
        ];

        home.packages = [ cfg.finalPackage ] ++ concatMap (feature: feature.packages) sortedEnabledFeatures;

        home.file = optionalAttrs (cfg.earlyInitFile != null && earlyContent != "") {
          ${cfg.earlyInitFile}.source = pkgs.writeText "early-init.el" earlyContent;
        };

        warnings = hmEmacsWarning;
      }

      (mkIf cfg.service.enable {
        services.emacs = {
          enable = true;
          package = cfg.finalPackage;
        };
      })
    ]
    ++ featureDefinitions
  ));
}
