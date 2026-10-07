# Marskal for Thunderbird

Adds mail to your Marskal inbox as tasks (ADR 0024). Each message becomes
one inbox task: the subject as the title, a `mid:` link back to the message,
and the sender, date, and text in the notes.

- The **Add to Marskal inbox** button on a displayed message lets you edit
  the title first.
- **Add to Marskal inbox** in the message list's context menu adds every
  selected message at once.

It only adds tasks. It keeps no copy of them and cannot read them.
Thunderbird 140 (the oldest supported ESR) and later.

```sh
devenv shell
npm install
npm run check      # type-check
npm test           # Node's test runner
npm run package    # builds dist/ and marskal-thunderbird.xpi
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

For development, the server is `http://marskal.localhost:8275`.
