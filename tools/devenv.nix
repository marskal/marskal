{ pkgs, config, ... }:
{
  # Repository-wide chores, not a program: releases (ADR 0038). Enter it
  # only for these; each component keeps its own devenv (ADR 0015).
  packages = [
    pkgs.changie
    pkgs.gh
    pkgs.git
    pkgs.jq
    pkgs.perl
  ];

  # Scripts, not tasks: in a terminal, devenv's task view keeps only the
  # last lines of a task's output, and what these print is the point.
  # Run them as `devenv shell release-preview`.
  scripts = {
    release-preview = {
      description = "Show the next version and its notes, changing nothing";
      exec = ''${config.devenv.root}/scripts/release --preview'';
    };
    release-pr = {
      description = "Open the release PR: changelog, version bumps, and all";
      exec = ''${config.devenv.root}/scripts/release'';
    };
    update-locks = {
      description = "Update every devenv.lock and flake.lock onto one nixpkgs";
      exec = ''${config.devenv.root}/scripts/update-locks'';
    };
  };
}
