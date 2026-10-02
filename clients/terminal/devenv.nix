{ ... }:
{
  # The terminal client, `marskal` (ADR 0020). It links sync/core by path.
  # nixpkgs' Rust: rustc, cargo, clippy, rustfmt, and rust-analyzer.
  languages.rust.enable = true;
}
