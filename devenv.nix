{ pkgs, ... }:
{
  # https://devenv.sh/packages/
  packages = [
    pkgs.rubyPackages.rails
  ];

  # https://devenv.sh/languages/
  languages = {
    ruby.enable = true;
    ruby.bundler.enable = true;
  };

  # See full reference at https://devenv.sh/reference/options/
}

