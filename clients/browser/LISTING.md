# Listings on addons.mozilla.org and the Chrome Web Store

The text for the extension's pages on addons.mozilla.org (AMO) and the
Chrome Web Store. Paste each section into the field it names; both stores
take the same text. Links go in the Homepage and Support fields.

## Name

Marskal

## Summary

Add web pages as tasks to the inbox of Marskal, an open-source,
self-hosted personal task manager.

## Description

Marskal is an open-source, self-hosted personal task manager: an inbox for
capturing what comes up, projects and nested tasks, tags, planned and due
dates, and tasks that repeat. The homepage has more on self-hosting it.

This extension turns web pages into tasks in your Marskal inbox, so a page
you need to come back to does not stay open in a tab.

- Choose **Add to Marskal inbox** in the toolbar. You can edit the task's
  title before adding it, and keep the text you selected on the page.
- Or right-click: **Add page to Marskal inbox** on a page, or **Add link to
  Marskal inbox** on a link.

Each task has the page's title, its address as the task's link, and the
text you selected, quoted in its notes.

To set it up, open the extension's options, enter your Marskal server's
address, and choose Sign in. The server opens in a new tab, where you
confirm a code and allow this device. The browser can then add tasks, but
not read them, and Sign out revokes its access.

**Data:** a page is sent only when you add it, and only to the Marskal
server you entered, over HTTPS: its title, its address, and the text you
selected. Nothing is sent to anyone else, and the extension collects
nothing about how you use it.

## Homepage

https://github.com/marskal/marskal

## Support site

https://github.com/marskal/marskal/issues

## License

Apache License 2.0

## Privacy policy

Marskal for browsers sends web pages that you choose to the Marskal server
that you enter in its options. It has no server of its own and sends
nothing to anyone else.

What is sent: when you add a page or a link to your Marskal inbox, with the
toolbar button or the context menu, the extension sends that page's title
and address, the text you selected on it, and for a link, the address of
the page it is on, to your Marskal server, which saves them as a task in
your account. The extension looks at a tab only when you add it; other
pages are not read or sent.

Why: to make a task of the page in your own task manager, with a link
back to it.

How: only over HTTPS. Signing in uses OAuth with the server; the extension
stores the access and refresh tokens and the server's address in the
browser's extension storage in your profile, and keeps no copy of the
pages or tasks. Sign out deletes the tokens and asks the server to revoke
them.

The extension collects no analytics, usage, or crash data. What the server
does with your tasks is up to whoever runs it, usually you.

## Chrome Web Store: privacy practices

- **Single purpose:** add the current web page or a link, as a task, to the
  inbox of the user's own Marskal server.
- **activeTab:** reads the title and address of the tab the user adds.
- **scripting:** reads the text the user selected in that tab.
- **contextMenus:** the Add page and Add link menu items.
- **notifications:** says whether a page added from the menu was added.
- **storage:** keeps the server's address and the sign-in tokens.
- **Host permission:** asked for at sign-in, for the user's server only.
- **Remote code:** none.
- **Data usage:** website content and web history (the pages the user
  adds), and authentication information (the tokens). Sent only to the
  user's server; not sold, not used for anything but adding the task.

## Notes for reviewers

Marskal is self-hosted. A test account on a Marskal server, for sign-in in
the extension's options:

- Server: <server URL>
- Email: <email>
- Password: <password>

Sign in in the options (a tab opens the server; sign in there with the
account above, confirm the code, and allow the device), open any page, and
choose Add to Marskal inbox in the toolbar. The task appears in the
server's Inbox.

The source archive builds the extensions with `npm ci` and `npm run
package` in `clients/browser`; the README there gives the Node.js and npm
versions.
