# Marskal for Thunderbird

Adds mail to your Marskal inbox as tasks (ADR 0024). Each message becomes
one inbox task: the subject as the title, a `mid:` link back to the message,
and the sender, date, and text in the notes.

- The **Add to Marskal inbox** button on a displayed message lets you edit
  the title first.
- **Add to Marskal inbox** in the message list's context menu adds every
  selected message at once.

It only adds tasks. It keeps no copy of them and cannot read them.
Thunderbird 140 (the oldest supported ESR) and later. It talks to the
server over HTTPS only. The source is at https://github.com/marskal/marskal,
in `clients/thunderbird`.

```sh
devenv shell
npm install
npm run check      # type-check
npm test           # Node's test runner
npm run package    # builds dist/ and marskal-thunderbird.xpi
npm run source     # the committed source, for the add-ons site
```

To try it, open Thunderbird's Add-ons Manager, choose *Debug Add-ons* from
the gear menu, and load `dist/manifest.json` as a temporary add-on. Or
install the `.xpi` from a file.

## Signing in

In the extension's options, enter the server's URL and choose *Sign in*.
Thunderbird asks for access to that server. Your browser then opens the
server, where you confirm the code, name the device, and allow it, as for
the terminal client. The client is `marskal-thunderbird`, with
`offline_access sync:write` only. *Sign out* revokes the device; Settings in
the web app lists it too.

The extension accepts only HTTPS, and turns an `http://` address into
`https://`. To sign in to the development server, run Phoenix with HTTPS
(see `web/config/dev.exs`) and have Thunderbird trust its certificate.

## Building

The add-ons site rebuilds the extension from its source to check the
`.xpi`. On any OS with Node.js 24.20.0 and npm 11.19.0
(https://nodejs.org/en/download), and `zip`:

```sh
npm ci
npm run package
```

`marskal-thunderbird.xpi` is the add-on. Its scripts are TypeScript bundled
by esbuild, not minified; the toolbar icon is Lucide's `inbox` with a style
added. `npm ci` installs exactly the versions in `package-lock.json`.

## Releasing

Raise `version` in `static/manifest.json`, commit, then run `npm run
package` and `npm run source`. Upload `marskal-thunderbird.xpi` to
addons.thunderbird.net and, when asked for source code, upload
`marskal-thunderbird-source.zip`: the committed `clients/thunderbird`,
without tests. The listing's text and privacy policy are in `LISTING.md`.
