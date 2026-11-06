/**
  NixOS module for Marskal: the release, Ory Hydra as its OAuth server
  (ADR 0021), a local Postgres database for each, and an nginx vhost with
  ACME. Hydra listens on localhost only; nginx proxies its public API, and
  its admin API stays private.

  The host picks the Postgres major (`services.postgresql.package`); it
  must be 18 or later. The app reaches Postgres over the unix socket with
  peer auth, so there is no database password. `SECRET_KEY_BASE` and `RELEASE_COOKIE` are
  generated on first start into `secretsFile` and kept across deploys.

  Admin commands run the release as the service user, with the service
  environment:

      sudo -u marskal marskal-server remote
      sudo -u marskal marskal-server eval "Marskal.Release.migrate()"
*/
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.marskal;
  stateDir = "/var/lib/marskal";

  environment = {
    PHX_SERVER = "true";
    PHX_HOST = cfg.host;
    PORT = toString cfg.port;
    DATABASE_URL = "ecto://marskal@localhost/marskal?socket_dir=/run/postgresql";
    RELEASE_TMP = "/run/marskal";
  };

  release = lib.getExe cfg.package;

  # Ory Hydra, the OAuth server (ADR 0021). Its public port sits behind
  # nginx on the same host; its admin port is only ever on localhost.
  hydra = cfg.hydra;
  hydraExe = lib.getExe hydra.package;
  hydraStateDir = "/var/lib/marskal-hydra";
  hydraEnvironment = {
    DSN = "postgres://marskal_hydra@/marskal_hydra?host=/run/postgresql&sslmode=disable";
  };
  hydraConfig = pkgs.writeText "hydra.json" (
    builtins.toJSON (
      import ./hydra-config.nix {
        inherit (cfg) host;
        inherit (hydra) publicPort adminPort;
      }
    )
  );
  hydraServiceConfig = {
    User = "marskal_hydra";
    Group = "marskal_hydra";
    EnvironmentFile = hydra.secretsFile;
    StateDirectory = "marskal-hydra";
    StateDirectoryMode = "0750";
    NoNewPrivileges = true;
    PrivateTmp = true;
    PrivateDevices = true;
    ProtectSystem = "strict";
    ProtectHome = true;
  };

  # Hydra's public API answers with redirects and JSON. nginx gives it the
  # headers MarskalWeb.SecurityHeaders and Plug.SSL give the app; Hydra
  # sets its own Cache-Control.
  hydraLocation = {
    proxyPass = "http://127.0.0.1:${toString hydra.publicPort}";
    extraConfig = lib.concatMapStrings (h: "add_header ${h} always;\n") [
      "Strict-Transport-Security \"max-age=63072000; includeSubDomains; preload\""
      "Content-Security-Policy \"default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'\""
      "Cross-Origin-Embedder-Policy require-corp"
      "Cross-Origin-Opener-Policy same-origin"
      "Cross-Origin-Resource-Policy same-site"
      "Permissions-Policy \"camera=(), geolocation=(), microphone=()\""
      "Referrer-Policy strict-origin-when-cross-origin"
      "X-Content-Type-Options nosniff"
      "X-DNS-Prefetch-Control off"
      "X-Frame-Options DENY"
      "X-Permitted-Cross-Domain-Policies none"
      "X-Robots-Tag \"noindex, nofollow\""
    ];
  };

  adminCommand = pkgs.writeShellScriptBin "marskal-server" ''
    set -a
    ${lib.toShellVars environment}
    . ${lib.escapeShellArg cfg.secretsFile}
    set +a
    exec ${release} "$@"
  '';
in
{
  options.services.marskal = {
    enable = lib.mkEnableOption "Marskal";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "marskal.packages.\${system}.default";
      description = "The Marskal release.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      example = "marskal.example";
      description = "Public host name. Sets `PHX_HOST` and the nginx vhost.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 4000;
      description = "Loopback port Phoenix listens on behind nginx.";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      default = "${stateDir}/secrets.env";
      description = ''
        Environment file with `SECRET_KEY_BASE` and `RELEASE_COOKIE`.
        Created with random values when missing. Optional Todoist import
        credentials (`TODOIST_CLIENT_ID`, `TODOIST_CLIENT_SECRET`, and
        `TODOIST_REDIRECT_URI`) can be added to the same file, and so can
        mail: `MAILER_ADAPTER` names a Swoosh adapter, `MAILER_FROM` is the
        sender, and each other `MAILER_<KEY>` is an adapter option
        (`MAILER_ADAPTER=Scaleway`, `MAILER_PROJECT_ID`, `MAILER_SECRET_KEY`).
      '';
    };

    hydra = {
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.ory-hydra;
        defaultText = lib.literalExpression "pkgs.ory-hydra";
        description = "Ory Hydra, the OAuth server (ADR 0021).";
      };

      publicPort = lib.mkOption {
        type = lib.types.port;
        default = 4444;
        description = "Loopback port of Hydra's public API, behind nginx.";
      };

      adminPort = lib.mkOption {
        type = lib.types.port;
        default = 4445;
        description = "Loopback port of Hydra's admin API. Never proxied.";
      };

      secretsFile = lib.mkOption {
        type = lib.types.path;
        default = "${hydraStateDir}/secrets.env";
        description = ''
          Environment file with Hydra's `SECRETS_SYSTEM`. Created with a
          random value when missing. Changing it invalidates every token.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # Primary keys default to uuidv7(), which Postgres has from 18.
        assertion = lib.versionAtLeast config.services.postgresql.package.version "18";
        message = "services.marskal needs services.postgresql.package 18 or later.";
      }
    ];

    users.users.marskal = {
      isSystemUser = true;
      group = "marskal";
      home = stateDir;
    };
    users.groups.marskal = { };

    # Named like its database, so peer auth lines up.
    users.users.marskal_hydra = {
      isSystemUser = true;
      group = "marskal_hydra";
      home = hydraStateDir;
    };
    users.groups.marskal_hydra = { };

    environment.systemPackages = [ adminCommand ];

    services.postgresql = {
      enable = true;
      ensureUsers = [
        { name = "marskal"; }
        { name = "marskal_hydra"; }
      ];
    };

    # Each database on the built-in provider with PG_UNICODE_FAST, and
    # glibc's C.UTF-8 for the other categories (ADR 0034), owned by its
    # role. ensureDatabases would copy template1 and its libc
    # locale, and ensureDBOwnership needs ensureDatabases. This runs after
    # ensureUsers in the same script, and only creates: a database made
    # another way is left as it is. The host's initdbArgs stay its own.
    systemd.services.postgresql-setup.script = lib.mkAfter (
      lib.concatMapStrings
        (database: ''
          psql -tAc "SELECT 1 FROM pg_database WHERE datname = '${database}'" | grep -q 1 \
            || psql -v ON_ERROR_STOP=1 -tAc "CREATE DATABASE ${database} OWNER ${database} TEMPLATE template0 ENCODING 'UTF8' LOCALE_PROVIDER builtin BUILTIN_LOCALE 'PG_UNICODE_FAST' LOCALE 'C.UTF-8'"
        '')
        [
          "marskal"
          "marskal_hydra"
        ]
    );

    systemd.services.marskal-hydra-secrets = {
      description = "Generate Hydra secrets";
      unitConfig.ConditionPathExists = "!${hydra.secretsFile}";
      path = [ pkgs.openssl ];
      script = ''
        umask 077
        tmp="$(mktemp ${lib.escapeShellArg hydra.secretsFile}.XXXXXX)"
        echo "SECRETS_SYSTEM=$(openssl rand -hex 32)" > "$tmp"
        mv "$tmp" ${lib.escapeShellArg hydra.secretsFile}
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "marskal_hydra";
        Group = "marskal_hydra";
        StateDirectory = "marskal-hydra";
        StateDirectoryMode = "0750";
      };
    };

    systemd.services.marskal-hydra = {
      description = "Ory Hydra for Marskal";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "postgresql.target"
        "marskal-hydra-secrets.service"
      ];
      after = [
        "network.target"
        "postgresql.target"
        "marskal-hydra-secrets.service"
      ];
      environment = hydraEnvironment;
      serviceConfig = hydraServiceConfig // {
        ExecStartPre = "${hydraExe} migrate sql up --read-from-env --yes";
        ExecStart = "${hydraExe} serve all --config ${hydraConfig}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # Hydra does not prune its own tables.
    systemd.services.marskal-hydra-janitor = {
      description = "Prune expired Hydra tokens and requests";
      requires = [ "postgresql.target" ];
      after = [ "postgresql.target" ];
      environment = hydraEnvironment;
      serviceConfig = hydraServiceConfig // {
        Type = "oneshot";
        ExecStart = "${hydraExe} janitor --read-from-env --tokens --requests --grants";
      };
    };

    systemd.timers.marskal-hydra-janitor = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        RandomizedDelaySec = "1h";
        Persistent = true;
      };
    };

    systemd.services.marskal-secrets = {
      description = "Generate Marskal secrets";
      unitConfig.ConditionPathExists = "!${cfg.secretsFile}";
      path = [ pkgs.openssl ];
      script = ''
        umask 077
        tmp="$(mktemp ${lib.escapeShellArg cfg.secretsFile}.XXXXXX)"
        {
          echo "SECRET_KEY_BASE=$(openssl rand -base64 64 | tr -d '\n')"
          echo "RELEASE_COOKIE=$(openssl rand -hex 32)"
        } > "$tmp"
        mv "$tmp" ${lib.escapeShellArg cfg.secretsFile}
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "marskal";
        Group = "marskal";
        StateDirectory = "marskal";
        StateDirectoryMode = "0750";
      };
    };

    systemd.services.marskal = {
      description = "Marskal";
      wantedBy = [ "multi-user.target" ];
      requires = [
        "postgresql.target"
        "marskal-secrets.service"
        "marskal-hydra.service"
      ];
      after = [
        "network.target"
        "postgresql.target"
        "marskal-secrets.service"
        "marskal-hydra.service"
      ];
      environment = environment // {
        HYDRA_ADMIN_URL = "http://127.0.0.1:${toString hydra.adminPort}";
        HYDRA_PUBLIC_URL = "https://${cfg.host}";
      };
      serviceConfig = {
        User = "marskal";
        Group = "marskal";
        EnvironmentFile = cfg.secretsFile;
        StateDirectory = "marskal";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "marskal";
        WorkingDirectory = stateDir;
        ExecStartPre = [
          ''${release} eval "Marskal.Release.migrate()"''
          ''${release} eval "Marskal.Release.ensure_oauth_clients()"''
        ];
        ExecStart = "${release} start";
        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
      };
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = lib.mkDefault true;
      virtualHosts.${cfg.host} = {
        forceSSL = true;
        enableACME = true;
        # OmniFocus imports may be up to 50 MB (MarskalWeb.Parsers.Multipart).
        extraConfig = ''
          client_max_body_size 55M;
        '';
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          proxyWebsockets = true;
        };
        # Hydra's public API (ADR 0021). Its admin API is never proxied.
        locations."/oauth2/" = hydraLocation;
        locations."= /.well-known/oauth-authorization-server" = hydraLocation;
        locations."= /.well-known/openid-configuration" = hydraLocation;
        locations."= /.well-known/jwks.json" = hydraLocation;
      };
    };
  };
}
