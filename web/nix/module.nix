/**
  NixOS module for Marskal: the release, a local Postgres database, and an
  nginx vhost with ACME.

  The host picks the Postgres major (`services.postgresql.package`); it
  must be 18 or later. The app reaches Postgres over the unix socket with
  peer auth, so there is no database password. `SECRET_KEY_BASE` and `RELEASE_COOKIE` are
  generated on first start into `secretsFile` and kept across deploys.

  Admin commands run the release as the service user, with the service
  environment:

      sudo -u marskal marskal remote
      sudo -u marskal marskal eval "Marskal.Release.migrate()"
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

  adminCommand = pkgs.writeShellScriptBin "marskal" ''
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
        Created with random values when missing.
      '';
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

    environment.systemPackages = [ adminCommand ];

    services.postgresql = {
      enable = true;
      ensureDatabases = [ "marskal" ];
      ensureUsers = [
        {
          name = "marskal";
          ensureDBOwnership = true;
        }
      ];
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
      ];
      after = [
        "network.target"
        "postgresql.target"
        "marskal-secrets.service"
      ];
      inherit environment;
      serviceConfig = {
        User = "marskal";
        Group = "marskal";
        EnvironmentFile = cfg.secretsFile;
        StateDirectory = "marskal";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "marskal";
        WorkingDirectory = stateDir;
        ExecStartPre = ''${release} eval "Marskal.Release.migrate()"'';
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
      };
    };
  };
}
