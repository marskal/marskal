# Shared code for the capture extensions

What the Thunderbird and browser extensions share (ADR 0024, ADR 0035):
signing in with the device grant, the account and its token refresh, the
push of `insert` commands, the options page's logic, the field limits, and
the stylesheet and logo.

Each extension depends on it as `file:../webext-common` and imports
`@marskal/webext-common/<module>`; esbuild bundles it into the extension.
It has no runtime dependencies, so nothing needs installing here for an
extension to build: the extension passes its own UUIDv7 generator to
`insertCommand`. `static/` is copied into each extension's `dist/`.

```sh
devenv shell
npm install
npm run check      # type-check
npm test           # Node's test runner
```
