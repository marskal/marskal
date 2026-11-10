# Contributing

## Changelog

A pull request that changes what a user or an operator sees adds a
changelog fragment ([ADR 0038](docs/adr/0038-changelog-and-releases.md)).
`changie` is in every devenv:

```sh
changie new
```

It asks for the component, the kind, and one sentence for the people who use
that component. A change to two components gets two fragments; a change in a
library (`core/replica`, `core/rules`, `clients/webext-common`) gets one for each program it
changes. The web app has an extra kind, **Upgrading**, for what someone
running it must do.

A refactor, a test, an ADR, or a CI change needs no fragment. Label that pull
request `no changelog`, or the Changelog check fails.

## Releasing

Marskal has one version for every component. A release is one pull request,
made by a script in the `tools/` devenv:

```sh
cd tools
devenv shell release-preview   # the next version and its notes
devenv shell release-pr        # open the release PR
```

`release-pr` works from `origin/master` in a worktree of its own, so the
checkout you are in is left alone. It runs `changie batch auto` and
`changie merge`, sets the new version in every component
(`tools/scripts/set-version`), commits on `release-v<version>`, and opens
the PR, labelled `no changelog`.

Merging that PR tags the merge commit `v<version>` and publishes the GitHub
release with its notes (`.github/workflows/release.yml`). Then ship the
components that have a section in that version: a host deploys the web app
by pointing its flake input at the tag. Raise `CURRENT_PROJECT_VERSION` for
every iOS upload, release or not.

To publish a version whose notes are already on `master` without a release
PR, run the Release workflow by hand with that version.

When a component's version moves to another file, or a component joins,
change `tools/scripts/set-version` and the paths `tools/scripts/release`
commits.

## Updating Nix inputs

Every devenv and flake follows one nixpkgs channel (ADR 0004), and each
flake.lock stays on its devenv.lock's nixpkgs. One script updates them all,
in the checkout you are in:

```sh
cd tools
devenv shell update-locks
```

It updates `web/devenv.lock`, copies that nixpkgs into every other
`devenv.lock` and `flake.lock`, and updates their other inputs on their own.
Dependabot does not read these locks.
