# The curried form: the feature name first, then the module arguments.
{ thisFeature }:
{ pkgs, ... }:
{
  order = 5;

  elisp = "(message \"curried feature ${thisFeature} with ${pkgs.lib.version})";
}
