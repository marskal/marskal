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

  # https://devenv.sh/processes/
  # `devenv up` starts Postgres (service) + Rails. Visit http://marskal.localhost:8275
  processes = {
    rails = {
      exec = "bundle exec rails server -b 127.0.0.1 -p 8275";
      after = [ "devenv:processes:postgres" ];
      ready = {
        http.get = {
          host = "127.0.0.1";
          port = 8275;
          path = "/up";
        };
        initial_delay = 1;
        period = 2;
        probe_timeout = 2;
      };
      # Rails has its own reloader; no need to restart the process on every save.
    };
  };

  enterShell = ''
    # App binstubs (bin/rails from Bundler). No nix/global rails package.
    export PATH="$PWD/bin:$PATH"
  '';

  # See full reference at https://devenv.sh/reference/options/
}

