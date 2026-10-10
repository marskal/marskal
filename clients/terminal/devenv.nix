{ ... }:
{
  # The terminal client, `marskal` (ADR 0020). It links sync/core by path.
  # nixpkgs' Rust: rustc, cargo, clippy, rustfmt, and rust-analyzer.
  languages.rust.enable = true;

  # Point `cargo run` at the local web app (web/, `devenv up`), not the
  # server you use day to day. Its database is its own: <server>.db.
  env.MARSKAL_SERVER = "http://marskal.localhost:8275";
}
