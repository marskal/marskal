{ pkgs, ... }:
{
  # The Rust client sync library (ADR 0018). Its own toolchain, not the web
  # app's (ADR 0015, ADR 0020). nixpkgs' Rust: rustc, cargo, clippy,
  # rustfmt, and rust-analyzer.
  languages.rust.enable = true;

  packages = [
    pkgs.changie # changelog fragments (ADR 0038)
  ];
}
