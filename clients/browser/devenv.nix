{ pkgs, ... }:
{
  # The browser extension (ADR 0035): TypeScript built with esbuild into a
  # Firefox and a Chromium extension, each zipped.
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
