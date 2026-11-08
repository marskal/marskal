# 0037. Development on GitHub

## Status

Proposed

## Context

Marskal is public under the Apache License 2.0. Its repository, issues, and
pull requests live on a self-hosted Forgejo, `gitte.hoegh.digital`, and PRs
are opened with `fj`. PRs #1–#141 and their reviews are there. `master` is
already on `github.com/marskal/marskal`.

Open source changes what the forge is for. It is where people find the
project, report a bug, and send a change. On a self-hosted forge each of
those starts with an account on that server, and few people make one.

The repository ships several programs: the web app, the terminal client,
the iOS app, two capture extensions, and later a desktop widget. None has
CI yet. The iOS app and `sync/ffi`'s XCFramework build only on macOS, and
the hosted runner for a self-hosted forge would be a Mac to own and keep
running. The stores the clients ship to (App Store Connect, the Firefox
and Chrome extension stores) have upload tooling written mostly for GitHub
Actions.

Alternatives considered:

- **Stay on the self-hosted Forgejo.** Rejected. Contribution needs an
  account on a private server, and macOS CI needs a Mac of our own.
- **Codeberg.** The same Forgejo, so `fj` and the workflow stay. Rejected:
  a smaller audience, and no macOS runners.
- **Develop on Forgejo, mirror to GitHub** with issues and PRs off. Rejected.
  Visible, but nobody can report or contribute where they find it, and CI
  stays without macOS.
- **GitLab.** Rejected. It offers this project nothing GitHub does not, and
  fewer potential contributors already have an account there.

## Decision

- The GitHub repository `marskal/marskal` is where development happens:
  code, issues, pull requests, CI, and releases.
- **CI is GitHub Actions.** A job enters the component's devenv, so CI runs
  what a developer runs: `mix precommit` in `web/`, `cargo test` in
  `sync/core` and `clients/terminal` (the fixture vectors included), the
  extensions' checks and tests, and the iOS build and tests on a macOS
  runner.
- `master` takes changes through pull requests only, and a PR merges when
  its CI passes. PRs keep merging with a merge commit, so stacked branches
  rebase cleanly.
- PRs are opened with `gh`, which replaces `fj` in `web/devenv.nix`. The
  review task for the user carries the GitHub PR URL.
- **Forgejo:** the existing repository is archived read-only and keeps
  PRs #1–#141. A Forgejo pull mirror of the GitHub repository keeps a copy
  of the code off GitHub.
- Production takes the web app's flake from GitHub
  (`github:marskal/marskal?dir=web`); the host's flake input changes once.
- Security reports go through GitHub's private vulnerability reporting,
  described in `SECURITY.md`.

## Consequences

- Anyone with a GitHub account can file an issue or open a PR. Stars,
  search, and packagers such as nixpkgs see the project.
- Public repositories get Actions minutes, macOS included, at no cost.
  Signing secrets for the stores live in GitHub's encrypted secrets.
- Issues, PRs, and reviews now depend on GitHub. Git history and the ADRs
  move anywhere; the pull mirror keeps the code, not the discussion.
- History before the move stays on Forgejo. A commit message that cites
  `#140` means a Forgejo PR; GitHub numbers its PRs from 1 again.
- Required next: issues and PRs on the GitHub repository, if not on yet;
  `CONTRIBUTING.md` (setup through devenv, the changelog fragment from
  [ADR 0038](0038-changelog-and-releases.md), and how agents are used);
  `SECURITY.md`; issue and PR templates; branch protection; the CI
  workflows; and, in `AGENTS.md`, `gh` in place of `fj`. Contributions come
  in under the Apache License 2.0 itself (section 5), with no sign-off or
  CLA.
