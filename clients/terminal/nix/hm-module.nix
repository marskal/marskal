/**
  Home Manager module for the terminal client, on Linux and macOS alike.

  The server is set through `MARSKAL_SERVER`, not config.toml: `marskal
  login` writes config.toml, which a store symlink would refuse. Sign in
  once by hand after switching:

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

    server = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://tasks.example.com";
      description = ''
        The server's base URL. Sets `MARSKAL_SERVER`, which overrides
        the server `marskal login` saved.
      '';
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

    home.sessionVariables =
      lib.optionalAttrs (cfg.server != null) { MARSKAL_SERVER = cfg.server; }
      // lib.optionalAttrs (!cfg.keychain) { MARSKAL_NO_KEYCHAIN = "1"; };
  };
}
