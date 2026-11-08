/**
  The Marskal release, built by `mix release`.

  Hex deps come from one fixed-output derivation. Its name carries a hash
  of mix.lock, so a lock change fails the build with a hash mismatch
  instead of silently reusing the old deps. Put the new hash in
  `depsHash`.

  npm packages come from assets/package-lock.json through importNpmLock,
  which fetches each tarball by the integrity hash in the lock, so there is
  no hash to update here. Only runtime dependencies are installed:
  devDependencies like TypeScript are for checking, not for the bundle.

  Three deps download at compile time, which the sandbox forbids:

  - esbuild uses nixpkgs' binary through `MIX_ESBUILD_PATH`
    (config/config.exs).
  - mdex_native gets its precompiled NIF from a pre-fetched cache
    directory. rustler_precompiled still checks the tarball against the
    checksum file shipped in the hex package.
  - ex_cldr downloads the locale data Marskal.Cldr names. The build fetches
    each file by the hash in cldr-locales.nix into priv/cldr/locales, where
    ex_cldr finds it. Run nix/update-cldr-locales after changing the
    locales or upgrading ex_cldr.
*/
{
  lib,
  stdenv,
  beamPackages,
  esbuild,
  importNpmLock,
  fetchurl,
  linkFarm,
  nodejs_24,
}:
let
  pname = "marskal";
  version = "0.2.0";

  depsHash = "sha256-OZqXPn7+t90YbHHa6qbC73ELvvO+xkHkyBE5vHwFaUY=";

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
      hash = "sha256:d9686d96edc922ceda2c8d10005b27a5dfbd1fe2883fc26b7bbef1c4b7a53c09";
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

  cldrVersion = builtins.head (
    builtins.match ''.*"ex_cldr": \{:hex, :ex_cldr, "([^"]+)".*'' mixLock
  );

  cldrLocales = linkFarm "cldr-locales" (
    lib.mapAttrsToList (locale: hash: {
      name = "${locale}.json";
      path = fetchurl {
        url = "https://raw.githubusercontent.com/elixir-cldr/cldr/v${cldrVersion}/priv/cldr/locales/${locale}.json";
        inherit hash;
      };
    }) (import ./cldr-locales.nix)
  );

  # The lock without its dev entries, and package.json to match, so
  # `npm ci` accepts it.
  npmPackage = removeAttrs (lib.importJSON ../assets/package.json) [ "devDependencies" ];
  npmLock = lib.importJSON ../assets/package-lock.json;
  npmRuntimeLock = npmLock // {
    packages = lib.filterAttrs (path: entry: !(entry.dev or false)) npmLock.packages // {
      "" = removeAttrs npmLock.packages."" [ "devDependencies" ];
    };
  };

  nodeModules = importNpmLock.buildNodeModules {
    package = npmPackage;
    packageLock = npmRuntimeLock;
    nodejs = nodejs_24;
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

  # Before compiling: LiveView links assets/node_modules into the colocated
  # hooks directory when it extracts them.
  # ex_cldr reads its locale files from priv/cldr.
  preBuild = ''
    ln -s ${nodeModules}/node_modules assets/node_modules
    mkdir -p priv/cldr/locales
    cp ${cldrLocales}/*.json priv/cldr/locales/
  '';

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
