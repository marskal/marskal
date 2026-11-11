{ pkgs, ... }:
{
  # UniFFI bindings over core/replica and core/rules for the iOS app
  # (ADR 0029, ADR 0039). Same nixpkgs Rust as those; the iOS targets
  # come from clients/ios.
  languages.rust.enable = true;

  packages = [
    pkgs.changie # changelog fragments (ADR 0038)
  ];
}
