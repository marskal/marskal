{ pkgs, config, ... }:
{
  # Repository-wide chores, not a program: releases (ADR 0038). Enter it
  # only for these; each component keeps its own devenv (ADR 0015).
  packages = [
    pkgs.changie
    pkgs.gh
    pkgs.git
    pkgs.perl
  ];

  tasks = {
    "release:preview" = {
      description = "Show the next version and its notes, changing nothing";
      exec = "${config.devenv.root}/scripts/release --preview";
    };
    "release:pr" = {
      description = "Open the release PR: changelog, version bumps, and all";
      exec = "${config.devenv.root}/scripts/release";
    };
  };
}
