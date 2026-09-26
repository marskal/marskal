/**
  Production build of the web app. Development uses devenv.nix instead.

  The flake lives in web/ because it builds this program only (ADR 0015).
  Reference it with `?dir=web`.
*/
{
  description = "Marskal web app";

  # Same nixpkgs as devenv, so production runs the toolchain tested locally.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./nix/package.nix {
          beamPackages = pkgs.beam.packages.erlang_29.overrideScope (
            final: prev: { elixir = prev.elixir_1_20; }
          );
        };
      });

      nixosModules.default = import ./nix/module.nix { inherit self; };
    };
}
