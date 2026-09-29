{ pkgs, ... }:
let
  beam = pkgs.beam.packages.erlang_29;
in
{
  packages = [
    pkgs.forgejo-cli # `fj`, for pull requests on gitte.hoegh.digital
    pkgs.libpq
    pkgs.pkg-config
  ];

  languages.elixir = {
    enable = true;
    package = beam.elixir_1_20;
  };

  languages.erlang = {
    enable = true;
    package = beam.erlang;
  };

  # npm for assets/, installed on shell entry. esbuild itself comes from the
  # esbuild Hex package.
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_24;
    directory = "assets";
    npm = {
      enable = true;
      install.enable = true;
    };
  };

  services.postgres = {
    enable = true;
    package = pkgs.postgresql_18;
    listen_addresses = "127.0.0.1";
    initialDatabases = [
      { name = "marskal_dev"; }
      { name = "marskal_test"; }
    ];
  };

  # `devenv up` starts Postgres and the Phoenix server.
  processes.server = {
    exec = "mix phx.server";
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
  };
}
