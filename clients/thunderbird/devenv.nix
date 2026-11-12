{ pkgs, ... }:
{
  # The Thunderbird extension (ADR 0024): TypeScript built with esbuild,
  # packed into an .xpi with zip.
  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_26;
    npm.enable = true;
  };
  packages = [
    pkgs.zip
    pkgs.changie # changelog fragments (ADR 0038)
  ];
}
