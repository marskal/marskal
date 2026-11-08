# 0038. Changelog and releases

## Status

Proposed

## Context

Marskal has no changelog, no tags, and no release step. Every component is
at `0.1.0`. Now that it is public, people who run the web app or install a
client need to know what changed and what to do about it.

The repository ships programs that reach people in different ways and on
their own schedules:

| Component | Reaches people through | Version lives in |
|-----------|------------------------|------------------|
| Web app (`web/`) | the NixOS module, on a host's schedule | `web/mix.exs`, `web/nix/package.nix` |
| Terminal client (`clients/terminal`) | a binary built from source | `Cargo.toml` |
| iOS app (`clients/ios`) | the App Store | `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`) |
| Browser extension (`clients/browser`) | the Firefox and Chrome stores | `static/manifest.json` |
| Thunderbird extension (`clients/thunderbird`) | the Thunderbird add-on store | `static/manifest.json` |

`sync/core`, `sync/ffi`, and `clients/webext-common` are libraries that
ship inside the programs above, not on their own.

Many PRs are open at once, often stacked, and agents write a lot of them.
Two PRs that both add a line under the same heading of one changelog file
conflict, and the forge's merge button cannot resolve that.

Alternatives considered:

- **A version per component**, each with its own changelog and tags.
  Rejected. Five version lines and a matrix of which client works with
  which server, for a project one person releases. A store needs a version
  that goes up, not one without gaps, so one shared version serves every
  store.
- **One `CHANGELOG.md` edited directly, with a merge driver**
  (`changelog-merge`, which understands Keep a Changelog). Rejected. The
  driver runs only in a clone set up for it, so a PR still conflicts on
  the forge until someone rebases it locally.
- **Generated from commits or PR titles** (git-cliff, release-please).
  Rejected as the changelog. It needs Conventional Commits or strict
  labels, commit messages are written for developers, and internal PRs
  would show up. A generated list can still help draft a release.
- **Other fragment tools.** towncrier needs Python; changesets is built
  around npm packages; knope is built around the package manifests it
  knows, and Marskal keeps versions in `mix.exs` and `project.yml` too.
  Rejected for changie, a single binary in nixpkgs that knows nothing
  about any language and groups entries by component.

## Decision

- **One version for Marskal.** Every component carries the same SemVer
  version, `0.x` for now: a minor version for something new or anything
  that breaks, a patch for fixes. A release is tagged `v<version>`, such as
  `v0.2.0`.
- **Only what changed ships.** A release where only the web app changed is
  deployed and nothing is uploaded to a store. A client skips the versions
  it did not ship in: the iOS app can go from 0.3.0 to 0.6.0. The iOS
  build number goes up on every upload, release or not.
- **One changelog**, `CHANGELOG.md` at the root, in Keep a Changelog form.
  Each release's notes are grouped by component, then by kind.
- **Fragments with changie.** A PR that changes what a user or an operator
  sees adds a fragment: one small YAML file under `.changes/unreleased/`,
  made with `changie new`. Each fragment names one component and one kind
  and says the change in a sentence for the people who use it. A PR that
  changes two components adds two fragments. `.changie.yaml` at the root
  lists the components and kinds; changie comes from nixpkgs through each
  component's devenv.
- **Kinds** follow Keep a Changelog: Added, Changed, Deprecated, Removed,
  Fixed, Security. The web app has one more, **Upgrading**: what an
  operator must do, such as a new setting, a Hydra change, or a slow
  migration.
- A change in a library gets a fragment for each program it changes. A
  refactor, a test, an ADR, or a change to CI needs none.
- **Release** in one PR:
  1. `changie batch auto` collects the unreleased fragments into the next
     version, and `changie merge` writes `CHANGELOG.md`.
  2. Set the new version in every file in the table above, whether that
     component changed or not, so the repository names one version.
  3. When the PR is merged, tag the merge commit `v<version>` and publish
     a GitHub release with that version's notes.
  4. Ship the components that have entries in that release.
- A host deploys a release by pointing its flake input at the tag. Store
  uploads stay manual until CI does them.
- CI fails a PR that touches a component's directory without a fragment,
  unless the PR has the `no changelog` label (ADR 0037).

## Consequences

- Fragments are new files, so PRs never conflict over the changelog, on the
  forge or in a rebase.
- "Marskal 0.6" means one thing everywhere, and a client and a server on
  the same version were released together. A bug report names one number.
- A client's version does not say whether that client changed; its section
  in the changelog does. An operator finds what to do under Upgrading.
- Every user-facing PR takes one more step. The CI check and a line in
  `AGENTS.md` make it part of the routine for agents too.
- Releasing is a deliberate step, not a side effect of merging.
- `0.1.0` is where every component stands now. The first release collects
  only the fragments written from here on; the changelog starts there, not
  at the project's beginning.
- Required next: `.changie.yaml`; changie in the devenvs; the CI check; a
  release checklist in `CONTRIBUTING.md`; and the rule in `AGENTS.md`.
  The desktop widget (ADR 0036) joins the components when it ships.
