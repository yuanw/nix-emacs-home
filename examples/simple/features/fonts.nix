# Fonts chosen in Nix, read by the Elisp in the sibling fonts.el.
{ exampleFonts, ... }:
{
  defvar = {
    example-mono-font = exampleFonts.mono;
    example-proportional-font = exampleFonts.proportional;
  };
}
