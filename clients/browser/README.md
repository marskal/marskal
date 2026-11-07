# Marskal for browsers

Adds web pages to your Marskal inbox as tasks (ADR 0035), in Firefox and
the Chromium browsers (Chrome, Edge, Brave, Vivaldi). Each page becomes one
inbox task: its title as the title, its address as the task's URL, and any
text you selected quoted in the notes.

- The **Add to Marskal inbox** button in the toolbar lets you edit the title
  first.
- **Add page to Marskal inbox** in a page's context menu adds it at once;
  **Add link to Marskal inbox** on a link adds the page it leads to.

It only adds tasks. It keeps no copy of them and cannot read them. It sees
a tab only when you add it. Firefox 140 (the oldest supported ESR) and
later, Chromium 120 and later. It talks to the server over HTTPS only. The
source is at https://github.com/marskal/marskal, in `clients/browser`;
signing in and sending tasks are in `clients/webext-common`, shared with
the Thunderbird extension.

```sh
devenv shell
npm install
npm run check      # type-check
npm test           # Node's test runner
npm run package    # builds dist/ and the two .zip files
npm run source     # the committed source, for addons.mozilla.org
```

To try it in Firefox, open `about:debugging`, choose *This Firefox*, then
*Load Temporary Add-on*, and pick `dist/firefox/manifest.json`. In Chrome,
open `chrome://extensions`, turn on *Developer mode*, choose *Load
unpacked*, and pick `dist/chromium`.

## Signing in

In the extension's options, enter the server's URL and choose *Sign in*.
The browser asks for access to that server, then opens the server in a
new tab, where you confirm the code, name the device, and allow it, as for
the terminal client. The client is `marskal-browser-extension`, with
`offline_access sync:write` only. *Sign out* revokes the device; Settings
in the web app lists it too.

The extension accepts only HTTPS, and turns an `http://` address into
`https://`. To sign in to the development server, run Phoenix with HTTPS
(see `web/config/dev.exs`) and have the browser trust its certificate.

## Building

addons.mozilla.org rebuilds the extension from its source to check it. The
source archive holds two folders: `clients/browser`, the extension, and
`clients/webext-common`, code it shares with the Thunderbird extension,
which npm links in. On any OS with Node.js 24.21.0 and npm 11.19.0
(https://nodejs.org/en/download), and `zip`:

```sh
cd clients/browser
npm ci
npm run package
```

`marskal-firefox.zip` is the Firefox add-on and `marskal-chromium.zip` the
Chromium one. Their scripts are TypeScript bundled by esbuild, not
minified; the icons are the logo, `clients/webext-common/static/logo.svg`,
drawn to PNG by resvg. `npm ci` installs exactly the versions in
`package-lock.json`.

## Releasing

Raise `version` in `static/manifest.json`, commit, then run `npm run
package` and `npm run source`. Upload `marskal-firefox.zip` to
addons.mozilla.org with `marskal-browser-source.zip` as its source code,
and `marskal-chromium.zip` to the Chrome Web Store, which takes no source.
The listings' text and privacy policy are in `LISTING.md`.
