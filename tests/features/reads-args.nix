{ testInjected, ... }:
{
  # `testInjected' comes from `_module.args' in ../config.nix.
  setq.test-injected = testInjected;
}
