{ pkgs, ... }:
{
  # The Thunderbird extension (ADR 0024): TypeScript built with esbuild,
  # packed into an .xpi with zip.
  languages.javascript = {
    enable = true;
    npm.enable = true;
  };
  packages = [ pkgs.zip ];
}
