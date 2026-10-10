/**
  The terminal client, `marskal` (ADR 0020), for Linux and macOS.
  Development uses devenv.nix instead.

  The flake lives in clients/terminal because it builds this program only
  (ADR 0015). Reference it with `?dir=clients/terminal`.
*/
{
  description = "Marskal terminal client";

  # Same channel as devenv.yaml (ADR 0004). Keep flake.lock on
  # devenv.lock's rev.
  inputs.nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      homeModules.default = import ./nix/hm-module.nix { inherit self; };
    };
}
