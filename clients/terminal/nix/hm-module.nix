/**
  Home Manager module for the terminal client, on Linux and macOS alike.

  `settings` becomes `$XDG_CONFIG_HOME/marskal/config.toml`, which
  `marskal` only reads; what it records itself goes to the state
  directory. Sign in once by hand after switching:

      marskal login
*/
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.marskal;
  toml = pkgs.formats.toml { };
  settings = lib.filterAttrs (_: v: v != null) cfg.settings;
in
{
  options.programs.marskal = {
    enable = lib.mkEnableOption "the Marskal terminal client";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "marskal.packages.\${system}.default";
      description = "The `marskal` package.";
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = toml.type;
        options.server = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "https://tasks.example.com";
          description = ''
            The server's base URL. Without it, `marskal` uses the server
            last signed in to.
          '';
        };
      };
      default = { };
      description = "Written to `$XDG_CONFIG_HOME/marskal/config.toml`.";
    };

    keychain = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Keep tokens in the OS keychain. When false, sets
        `MARSKAL_NO_KEYCHAIN=1`, and tokens go to a file readable by the
        user alone under `$XDG_STATE_HOME/marskal`. Turn it off where there
        is no Secret Service, such as a headless Linux machine.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    xdg.configFile."marskal/config.toml" = lib.mkIf (settings != { }) {
      source = toml.generate "marskal-config.toml" settings;
    };

    home.sessionVariables = lib.mkIf (!cfg.keychain) { MARSKAL_NO_KEYCHAIN = "1"; };
  };
}
