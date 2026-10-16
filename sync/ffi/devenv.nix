{ ... }:
{
  # UniFFI bindings over sync/core for the iOS app (ADR 0029). Same
  # nixpkgs Rust as sync/core; the iOS targets come from clients/ios.
  languages.rust.enable = true;
}
