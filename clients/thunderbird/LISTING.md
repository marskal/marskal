# Listing on addons.thunderbird.net

The text for the add-on's page on addons.thunderbird.net (ATN). Paste each
section into the field it names. ATN allows no links in the description;
they go in the Homepage and Support fields.

## Name

Marskal for Thunderbird

## Summary

Add mail as tasks to the inbox of Marskal, an open-source, self-hosted
personal task manager.

## Description

Marskal is an open-source, self-hosted personal task manager: an inbox for
capturing what comes up, projects and nested tasks, tags, planned and due
dates, and tasks that repeat. The homepage says how to self-host it.

This add-on turns mail into tasks in your Marskal inbox, so a message that
needs doing can leave your mail inbox.

- With a message open, choose **Add to Marskal inbox** in its header. You
  can edit the task's title before adding it.
- In the message list, select messages and choose **Add to Marskal inbox**
  in the context menu. Each one becomes a task.

Each task has a title from the subject (or the sender, when there is none),
a link back to the message that opens it in Thunderbird, and the sender,
date, and text in its notes.

To set it up, open the add-on's options, enter your Marskal server's
address, and choose Sign in. Your browser opens the server, where you
confirm a code and allow this device. Thunderbird can then add tasks, but
not read them, and Sign out revokes its access.

**Data:** a message is sent only when you add it, and only to the Marskal
server you entered, over HTTPS: its subject, sender, date, Message-ID, and
text. Nothing is sent to anyone else, and the add-on collects nothing about
how you use it.

## Homepage

https://github.com/marskal/marskal

## Support site

https://github.com/marskal/marskal/issues

## License

Apache License 2.0

## Privacy policy

Marskal for Thunderbird sends mail that you choose to the Marskal server
that you enter in its options. It has no server of its own and sends
nothing to anyone else.

What is sent: when you add a message to your Marskal inbox, with the
button in the message header or the message list's context menu, the
add-on sends that message's subject, sender, date, Message-ID, and readable
text to your Marskal server, which saves them as a task in your account.
Messages you do not add are not read or sent.

Why: to make a task of the message in your own task manager, with a link
back to the message.

How: only over HTTPS. Signing in uses OAuth with the server; the add-on
stores the access and refresh tokens and the server's address in
Thunderbird's extension storage in your profile, and keeps no copy of the
messages or tasks. Sign out deletes the tokens and asks the server to
revoke them.

The add-on collects no analytics, usage, or crash data. What the server
does with your tasks is up to whoever runs it, usually you.

## Notes for reviewers

Paste into the Whiteboard field under Technical Details.

Marskal is self-hosted. A test account on a Marskal server, for sign-in in
the add-on's options:

- Server: <server URL>
- Email: <email>
- Password: <password>

Sign in in the options (the browser opens the server; sign in there with
the account above and allow the device), open a message, and choose Add to
Marskal inbox. The task appears in the server's Inbox.

The source archive builds the `.xpi` with `npm ci` and `npm run package`;
its README gives the Node.js and npm versions.
