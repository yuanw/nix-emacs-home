# nix-emacs-home

Configure Emacs with Home Manager, in feature files.

Each feature is one small file that says everything about one slice of the
editor — the Emacs Lisp packages it needs, the external programs it shells out
to, its Elisp, and the Emacs variables it wants set, given as Nix values:

```nix
# features/git.nix
{ pkgs, ... }:
{
  epkgs = epkgs: [ epkgs.magit ];            # Emacs Lisp packages
  packages = [ pkgs.git pkgs.delta ];         # ordinary Home Manager packages
  setopt.magit-diff-visit-prefer-worktree = true;   # a defcustom, from Nix
  elispFile = ./git.el;                       # or `elisp = "...";`
}
```

All features are collected in one pass and installed as a single
`emacs.pkgs.withPackages` package, so a feature never has to wrap Emacs itself
and two features cannot fight over the wrapper.  The Elisp ends up in a
generated `default.el` that ships as a package of its own: Emacs loads it the
way it would load `init.el`, it is byte-compiled at build time, and a typo in
your config fails `nix build` instead of Emacs startup.

```
$ nix build .#initFile && cat result     # see what your config generated
```

## Install

```nix
# flake input
inputs.nix-emacs-home.url = "github:yuanw/nix-emacs-home";

# somewhere in your Home Manager modules
home-manager.sharedModules = [ inputs.nix-emacs-home.hmModules.default ];

emacs = {
  enable = true;
  featureDirs = [ ./emacs/features ];
};
```

`emacs.enable = false` removes Emacs and everything the features would have
installed.  Do not enable Home Manager's own `programs.emacs` as well; it wraps
Emacs a second time.

## Feature files

A feature file is any `*.nix` file in a `featureDirs` directory whose name does
not start with `_`.  The feature is named after the file (`features/git.nix` is
the `git` feature), and if a `git.el` sits next to it, that file becomes the
feature's `elispFile`.  `_`-prefixed files are ignored, so features can share
code:

```nix
# features/_packages.nix — an overlay, not a feature
final: _prev: {
  my-mode = final.trivialBuild {
    pname = "my-mode";
    version = "0.1";
    src = ./my-mode.el;
  };
}
```

```nix
# features/my-mode.nix
{
  overlay = import ./_packages.nix;
  epkgs = epkgs: [ epkgs.my-mode ];
}
```

A file may be a plain attribute set or a function of the module arguments it
needs:

```nix
{ pkgs, myFonts, ... }:   # `myFonts' comes from `_module.args.myFonts`
{
  defvar = { my-mono-font = myFonts.mono; };
  elisp = "(set-face-attribute 'default nil :family my-mono-font)";
}
```

Anything you put in `_module.args` is available to feature files this way,
which is how configuration owned by someone else — a host's font choice,
another module's enable flag — reaches a feature.  A feature file may not read
`config.emacs.*`.

Features can also be written inline, and merge with the file of the same name
(list options concatenate, so this is how a host extends a feature without
editing it):

```nix
emacs.features.git.packages = [ pkgs.delta ];
emacs.features.lsp.enable = false;
```

## Feature options

| Option | Meaning |
| --- | --- |
| `enable` | Turn the feature off without deleting the file. |
| `order` | Position in the generated init file. Smaller first; use e.g. `-10000` for a prelude, `10000` for a postlude. |
| `epkgs` | `epkgs: [ epkgs.magit ]` — Emacs Lisp packages, from the package set that already contains every feature's `overlay`. |
| `requireEpkgs` | `false` to keep this feature's packages off the startup path: they stay on the load path and their `<package>-autoloads.el` is still loaded, but nothing is `(require)`d. Use it for a feature whose Elisp is all `use-package`. |
| `overlay` | `final: prev: { ... }` — packages not in nixpkgs, or patched versions of the ones in it. |
| `packages` | Ordinary Home Manager packages: the external programs this feature's modes call. |
| `elisp` | Elisp written inline in Nix. |
| `elispFile` | Elisp in its own file. Both may be set; the file comes first. |
| `defvar` | `(defvar NAME VALUE)` with a Nix value — variables your own Elisp reads. A value of `{ value = ...; doc = "..."; }` adds a docstring. |
| `setq` | `(setq NAME VALUE)` with Nix values. |
| `setopt` | `(setopt NAME VALUE)` — `defcustom`s; unlike `setq` this runs the option's `:set` function. |

## Nix values as Emacs variables

`null` → `nil`, `true` → `t`, numbers stay numbers, paths and derivations become
their store-path string, lists become lists, attribute sets become alists.  A
string that starts like Elisp — with `'`, `#'` or `(` — is inserted verbatim,
which is how you pass symbols and quoted forms:

```nix
setq = {
  confirm-nonexistent-file-or-buffer = false;
  completion-ignored-extensions = [ ".hi" ".o" ];
  uniquify-buffer-name-style = "'post-forward";
  xref-show-xrefs-function = "#'consult-xref";
  org-todo-keywords = { _elisp = "'((sequence \"TODO\" \"DONE\"))"; };
};
```

The `{ _elisp = ...; }` form is the escape hatch for anything the printer cannot
express (property lists, backquoted forms).  The same printer backs
`emacs.earlyDefvar`, `emacs.earlySetq` and `emacs.earlySetopt`.

## Module options

| Option | Meaning |
| --- | --- |
| `enable` | Install the configured Emacs and everything the features need. |
| `package` | An **unwrapped** Emacs: `pkgs.emacs`, `pkgs.emacs-git`, a patched one. |
| `featureDirs` | Directories of feature files. |
| `features` | Features (or overrides of ones coming from files). |
| `overlay` | Overlay for packages shared by several features. |
| `pedantic` | Turn byte-compilation warnings into build errors. |
| `earlyElisp`, `earlyElispFile`, `earlyDefvar`, `earlySetq`, `earlySetopt` | Content of `early-init.el`: faces, frame parameters, anything that must happen before the GUI starts. |
| `earlyInitFile` | Where to write it (`".emacs.d/early-init.el"` by default, `null` to write nothing). |
| `service.enable` | Also enable `services.emacs`, so `emacsclient` has a daemon to attach to. |
| `finalPackage` | Read the built Emacs when something else needs its store path (`EDITOR`, a launchd/systemd unit). |

## Notes

- The generated init file uses lexical binding, like any package would.
- Byte compilation evaluates top-level forms, so a `setopt`/`setq` of a package
  variable runs when Emacs loads the config, not when it builds.  If a mode
  warns about an unknown function at compile time, `require` it first, or leave
  `pedantic` off.
- `emacs.finalPackage` is the store path that says "my Emacs config changed" —
  useful in a service environment so a rebuild actually restarts the daemon.

## Tests

```
nix flake check --system $(nix eval --raw nixpkgs#system)
```

The `tests` check evaluates a Home Manager configuration built from
`tests/config.nix` and `tests/features/` and asserts on the generated Elisp, the
`home.packages` it produces, the ordering, disabled features and the error
messages.  `nix build .#emacs` builds the example in `examples/simple`, which is
what exercises the overlay and package wiring and byte-compiles the result.

## Hacking

```
nix develop       # treefmt, git, gh, nix-tree
treefmt .         # format every file — Nix only, for now
nix flake check   # eval tests, example build, and formatting
```

`flake.checks.treefmt` runs `treefmt --fail-on-change` on the project root, so
unformatted Nix fails the check; `nix fmt` uses the same treefmt config.

## Related work

- [nima](https://github.com/jian-lin/nima) — the same idea as a Nixpkgs
  overlay; it produces an Emacs package rather than a Home Manager module, so
  features there cannot declare ordinary packages or reach `config`.
- [rycee's emacs.nix](https://git.sr.ht/~rycee/configurations/tree/master/item/user/emacs.nix)
  — feature-shaped config on top of Home Manager's `use-package` generator.
