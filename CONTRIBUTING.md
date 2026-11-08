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
library (`sync/core`, `clients/webext-common`) gets one for each program it
changes. The web app has an extra kind, **Upgrading**, for what someone
running it must do.

A refactor, a test, an ADR, or a CI change needs no fragment. Label that pull
request `no changelog`, or the Changelog check fails.

## Releasing

Marskal has one version for every component. A release is one pull request,
labelled `no changelog`:

1. `changie batch auto` collects the fragments into the next version, and
   `changie merge` rewrites `CHANGELOG.md`. `changie next auto` shows the
   version first.
2. Set that version in every component, changed or not:
   - `web/mix.exs` and `web/nix/package.nix`
   - `clients/terminal/Cargo.toml` (then `cargo build` there, for
     `Cargo.lock`)
   - `MARKETING_VERSION` in `clients/ios/project.yml`
   - `clients/browser/static/manifest.json`
   - `clients/thunderbird/static/manifest.json`
3. Merge, then tag the merge commit and publish the release:

   ```sh
   git tag v0.2.0 <merge commit> && git push origin v0.2.0
   gh release create v0.2.0 --notes-file .changes/0.2.0.md
   ```

4. Ship the components that have a section in that version. A host deploys
   the web app by pointing its flake input at the tag. Raise
   `CURRENT_PROJECT_VERSION` for every iOS upload, release or not.
