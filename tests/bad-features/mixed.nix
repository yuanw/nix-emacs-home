# Used by the test suite: a feature file cannot mix feature options with Home
# Manager options, this must be an error rather than a confusing unknown-option
# message.
{
  elisp = "(message \"mixed\")";
  home.sessionVariables.SHOULD_NOT_WORK = "yes";
}
