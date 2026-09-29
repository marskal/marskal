/**
  The Marskal release, built by `mix release`.

  Hex deps come from one fixed-output derivation. Its name carries a hash
  of mix.lock, so a lock change fails the build with a hash mismatch
  instead of silently reusing the old deps. Put the new hash in
  `depsHash`.

  Two deps download binaries at compile time, which the sandbox forbids:

  - esbuild uses nixpkgs' binary through `MIX_ESBUILD_PATH`
    (config/config.exs).
  - mdex_native gets its precompiled NIF from a pre-fetched cache
    directory. rustler_precompiled still checks the tarball against the
    checksum file shipped in the hex package.
*/
{
  lib,
  stdenv,
  beamPackages,
  esbuild,
  fetchurl,
  linkFarm,
}:
let
  pname = "marskal";
  version = "0.1.0";

  depsHash = "sha256-dNFGzEZGwBhybuivfATxhbq7V84KtrpNby9DeCSCUxk=";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../mix.exs
      ../mix.lock
      ../config
      ../lib
      ../priv
      ../assets
    ];
  };

  mixLock = builtins.readFile ../mix.lock;
  lockDigest = builtins.substring 0 12 (builtins.hashString "sha256" mixLock);

  mdexNativeVersion = builtins.head (
    builtins.match ''.*"mdex_native": \{:hex, :mdex_native, "([^"]+)".*'' mixLock
  );

  # One entry per system we build on. Hashes are the sha256 values from
  # deps/mdex_native/checksum-Elixir.MDExNative.Native.exs.
  mdexNativeNifs = {
    x86_64-linux = {
      triple = "x86_64-unknown-linux-gnu";
      hash = "sha256:963238414ea5a6bb4545986c09c825dffcd75e9327db9ab7306fb1aa6cbd4cec";
    };
  };

  mdexNativeNif =
    let
      nif =
        mdexNativeNifs.${stdenv.hostPlatform.system}
          or (throw "marskal: no mdex_native NIF listed for ${stdenv.hostPlatform.system}");
      file = "libmdex_native_nif-v${mdexNativeVersion}-nif-2.15-${nif.triple}.so.tar.gz";
    in
    {
      name = file;
      path = fetchurl {
        url = "https://github.com/leandrocp/mdex_native/releases/download/v${mdexNativeVersion}/${file}";
        inherit (nif) hash;
      };
    };

  mixFodDeps = beamPackages.fetchMixDeps {
    pname = "${pname}-deps-${lockDigest}";
    inherit version src;
    hash = depsHash;
  };
in
beamPackages.mixRelease {
  inherit
    pname
    version
    src
    mixFodDeps
    ;

  env = {
    MIX_ESBUILD_PATH = lib.getExe esbuild;
    RUSTLER_PRECOMPILED_GLOBAL_CACHE_PATH = linkFarm "rustler-precompiled-cache" [ mdexNativeNif ];
  };

  # Compile first: esbuild bundles the colocated hooks and CSS that the
  # LiveView compiler writes under _build.
  postBuild = ''
    mix do deps.loadpaths --no-deps-check, assets.deploy
  '';

  meta = {
    description = "Personal task manager";
    mainProgram = "marskal";
    platforms = lib.attrNames mdexNativeNifs;
  };
}
