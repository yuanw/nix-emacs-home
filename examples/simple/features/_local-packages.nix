# Packages this configuration provides itself, shared by the features that need
# them.  Files starting with `_' are not features.
final: _prev:
{
  example-minor = final.trivialBuild {
    pname = "example-minor";
    version = "0.1";
    src = ./example-minor.el;
  };
}
