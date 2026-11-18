/**
  The terminal client, `marskal` (ADR 0020).

  It links core/replica, core/rules, and clients/shell-common by path, so
  the source is those directories and its own, laid out as in the
  repository. Crates come from Cargo.lock by the checksums in it, so
  there is no hash to update here when the lock changes.

  SQLite comes from nixpkgs: its cargo setup hook sets
  LIBSQLITE3_SYS_USE_PKG_CONFIG, which makes rusqlite link the system
  library instead of building its `bundled` copy. Everything else native
  is built from source by Cargo: TLS (rustls), and the keychain (zbus on
  Linux, the Security framework on macOS, which the darwin stdenv's SDK
  provides).
*/
{
  lib,
  rustPlatform,
  pkg-config,
  sqlite,
}:
let
  root = ../../..;
in
rustPlatform.buildRustPackage {
  pname = "marskal";
  version = (lib.importTOML ../Cargo.toml).package.version;

  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      ../Cargo.toml
      ../Cargo.lock
      ../src
      (root + "/core/replica/Cargo.toml")
      (root + "/core/replica/src")
      (root + "/core/rules/Cargo.toml")
      (root + "/core/rules/src")
      (root + "/clients/shell-common/Cargo.toml")
      (root + "/clients/shell-common/src")
    ];
  };

  cargoLock.lockFile = ../Cargo.lock;
  cargoRoot = "clients/terminal";
  buildAndTestSubdir = "clients/terminal";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ sqlite ];

  meta = {
    description = "Marskal tasks from the terminal, for people and agents";
    mainProgram = "marskal";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
