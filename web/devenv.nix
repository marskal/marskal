{ pkgs, ... }:
let
  beam = pkgs.beam.packages.erlang_29;
in
{
  packages = [
    pkgs.forgejo-cli # `fj`, for pull requests on gitte.hoegh.digital
    pkgs.libpq
    pkgs.ory-hydra # the OAuth 2.1 server (ADR 0021)
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
    port = 8271; # off the default, so other devenvs do not clash
    initialDatabases = [
      { name = "marskal_dev"; }
      { name = "marskal_test"; }
      { name = "marskal_hydra"; }
    ];
  };

  # services.postgres puts psql on the PATH and sets PGHOST and PGPORT. The
  # role is the login user, psql's default; this names the database, so a
  # bare `psql` opens the dev one. Mix reads its databases from config/.
  env.PGDATABASE = "marskal_dev";

  # Ory Hydra, the OAuth server (ADR 0021). Its own database in the same
  # cluster, created here for clusters made before it existed.
  processes.hydra = {
    exec = ''
      psql -h 127.0.0.1 -p "$PGPORT" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = 'marskal_hydra'" | grep -q 1 \
        || createdb -h 127.0.0.1 -p "$PGPORT" marskal_hydra
      export DSN="postgres://$USER@127.0.0.1:$PGPORT/marskal_hydra?sslmode=disable"
      hydra migrate sql up --read-from-env --yes
      hydra serve all --dev --config config/hydra.dev.yml &
      hydra=$!
      trap 'kill $hydra' TERM INT

      # The OAuth clients, from the files the release also uses.
      until curl -sf http://127.0.0.1:8277/health/ready > /dev/null; do sleep 1; done
      for spec in priv/hydra/clients/*.json; do
        id=$(sed -n 's/.*"client_id": *"\([^"]*\)".*/\1/p' "$spec")
        curl -sf -H content-type:application/json -X PUT "http://127.0.0.1:8277/admin/clients/$id" -d @"$spec" > /dev/null \
          || curl -sf -H content-type:application/json -X POST http://127.0.0.1:8277/admin/clients -d @"$spec" > /dev/null
      done
      wait $hydra
    '';
    after = [ "devenv:processes:postgres" ];
  };

  # Hydra does not prune its own tables (ADR 0021).
  scripts.hydra-janitor.exec = ''
    DSN="postgres://$USER@127.0.0.1:$PGPORT/marskal_hydra?sslmode=disable" \
      hydra janitor --read-from-env --tokens --requests --grants
  '';

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
