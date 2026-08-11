{ pkgs, ... }:
{
  # https://devenv.sh/packages/
  packages = [
    pkgs.libpq
    pkgs.pkg-config
  ];

  # https://devenv.sh/languages/
  languages = {
    ruby.enable = true;
    ruby.bundler.enable = true;
  };

  # https://devenv.sh/services/
  services.postgres = {
    enable = true;
    package = pkgs.postgresql_18;
    listen_addresses = "127.0.0.1";
    initialDatabases = [ { name = "marskal_development"; } { name = "marskal_test"; } ];
  };

  enterShell = ''
    # App binstubs (bin/rails from Bundler). No nix/global rails package.
    export PATH="$PWD/bin:$PATH"
  '';

  # See full reference at https://devenv.sh/reference/options/
}

