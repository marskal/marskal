# Changelog

What changed in each release of Marskal, by component. One version
covers every component; a component without a section did not change
(ADR 0038).

## 0.4.0 - 2026-11-21

### Web

#### Added

- The Inbox link shows how many tasks are waiting to be processed. ([#190](https://github.com/marskal/marskal/pull/190))

#### Changed

- The current sidebar view is highlighted like a selected project, with the disclosure triangle inside the bar, and hovering a row shows a lighter highlight. ([#190](https://github.com/marskal/marskal/pull/190))
- The Review list no longer says how long a project has been due. ([#195](https://github.com/marskal/marskal/pull/195))
- The header badge takes its own color, so two people with the same initials are easy to tell apart. ([#197](https://github.com/marskal/marskal/pull/197))

### Browser extension

#### Added

- A Marskal release that changes the browser extension now has its Firefox and Chromium packages attached on GitHub, with their source. ([#196](https://github.com/marskal/marskal/pull/196))

### Thunderbird extension

#### Added

- A Marskal release that changes the Thunderbird extension now has its .xpi attached on GitHub, with its source. ([#196](https://github.com/marskal/marskal/pull/196))

## 0.3.0 - 2026-11-17

### Web

#### Added

- A Review view lists the projects due for review, with a count in the sidebar. Open one to look it over and mark it reviewed, and the next one due follows. Set how often a project is reviewed in its inspector, and the interval new projects take in Settings.
- Set a name in Settings, or when you register; the header shows its initials instead of your email.
- The sync API turns away an app or extension older than the server supports, and tells it which version to update to.

#### Changed

- The field that adds a task now sits below the list on project, tag, and inbox pages, and the task it adds goes at the bottom. A tag page lists its tasks oldest first. Captures from elsewhere still go to the top of the inbox.

#### Fixed

- Typing Chinese, Japanese, or Korean, the Enter that confirms a character no longer saves a date or picks an option in Go to or a picker, and selecting notes text by dragging out of the notes window no longer closes it.

### Terminal

#### Added

- When the server needs a newer marskal, syncing says which version to update to, and exits with code 6.

#### Security

- Saving your sign-in now makes the token file readable only by you, also when an older file had looser permissions.

### iOS

#### Added

- Add a task straight into a project, or as a subtask from a task's menu or detail, with its Defer, Planned, Due, and tags chosen as you capture it. Pick a place by typing part of a project or folder name, as on the web.
- When the server needs a newer version of the app, Marskal says which one, and keeps your changes to send after the update.

### Browser extension

#### Added

- When the server needs a newer version of the extension, adding a task says which one.

### Thunderbird extension

#### Added

- When the server needs a newer version of the extension, adding a task says which one.

## 0.2.0 - 2026-11-08

### Web

#### Added

- The sidebar shows which version of Marskal is running, at its bottom.

#### Changed

- Task rows mark Defer with an hourglass, Planned with a calendar, and Due with an alarm clock instead of words, and the inspector labels its date fields with the same icons.

#### Fixed

- Live reload works again in development, so saving a file reloads the open browser tab.

### iOS

#### Added

- Set a task's Defer, Planned, and Due in its detail, on a calendar that starts your week where your preferences do, with Today, Tomorrow, and Next Week a tap away. Defer can be indefinite.
- Task lists show each task's Defer, Planned, and Due under its title: the time when it is today, otherwise the day.

#### Changed

- Deferred tasks and projects are hidden from lists until their Defer passes. The Show Deferred button in the toolbar brings them back, on that device.

## 0.1.0 - 2026-11-08

### Web

#### Added

- Capture tasks into the Inbox, then move them to a project or to No project. The Open tasks stream lists what is ready to do. A task is To-Do, Done, or Dropped.
- Projects, filed in project folders that nest. Tasks nest under tasks as an outline: drag a row to reorder or indent it, and collapse what you are not working on.
- Nested tags on tasks and projects. A project's tags count for its tasks, and each tag has a page. A tag can be Active, On Hold, or Dropped; an on-hold or dropped tag makes its tasks unavailable.
- Defer, Planned, and Due dates on tasks and projects. The agenda lists each day's planned and due items, overdue ones included, and deferred tasks wait until their day.
- Repeating tasks and projects: every few minutes to every few years, on chosen weekdays or days of the month (also counted from the end), on a fixed schedule or counted from completion, ending on a date or after a number of times. The next occurrence keeps the subtasks, and a task shows its earlier occurrences.
- A URL on each task and project, and a flag to mark what matters.
- Import from Todoist and from OmniFocus backups: folders, projects, tags, subtasks, dates, and repeats. Importing again updates what you have not changed since. Anything an import could not bring over is tagged "Import problems", with a note saying what.
- Type dates as you would say them, such as "tomorrow", "next fri evening", "in 2 weeks", or "i morgen", in English or Danish, or pick one from a calendar.
- Go to any view, project, folder, or tag by typing its name. The same picker moves a task.
- The inspector edits the selected task: title, URL, notes (in a wide window when they are long), place, tags, dates, flag, and repeat.
- Rearrange folders, projects, and tags as outlines in the sidebar, and collapse them.
- A layout for phones, with a menu drawer, a tab bar, and an add button on every page. The web app can be installed to the home screen.
- Light, dark, and automatic themes, and a choice of standard or Vim keyboard shortcuts.
- Preferences for time zone, locale, first day of the week, and home view. Dates and times follow the chosen locale.
- Show done, dropped, and deferred items when you ask for them. Lists show empty states, and a project shows its task counts.
- Accounts confirm their email address, passwords can be reset, and logging in returns you to the page you were on.
- Sign in apps and devices with a code (the OAuth device grant, through Ory Hydra), and see or sign out devices under Security in the settings.
- A sync API for offline clients: a snapshot and then the changes after it, commands pushed from the device, and a live event stream when your data changes.
- A tab left open across an update asks to reload, and reloads by itself while it is in the background.
- A NixOS package and module, with Postgres and Ory Hydra on the same host, and a health URL that checks the database.

#### Security

- Pages send the OWASP security headers, and cross-site page requests are refused by their Fetch Metadata.

#### Upgrading

- Databases use Postgres's built-in collation, `PG_UNICODE_FAST` (ADR 0034). A database created before cannot be switched: dump it without `--create` and restore it into one created the new way. This applies to `marskal_hydra` too.

### Terminal

#### Added

- `marskal`, a terminal client that works offline: add, list, show, edit, complete, drop, move, and tag tasks, then sync. Every command can answer in JSON for scripts and agents.
- Sign in with a code shown in the terminal and approved in the browser. Tokens are kept in the system keychain, or in a private file where there is none.
- Dates can be typed as shorthand, the same way as on the web, and tasks carry their URL and flag.
- A Nix package.

#### Security

- The data directory, which holds every task, is created readable by you alone.

### iOS

#### Added

- An iOS app that works offline and syncs: the Inbox, today's agenda, Open tasks, projects and folders, tags, and each task's detail and notes.
- Capture tasks, check them off, and move them between the Inbox and projects.
- Home screen widgets, one of them showing today's agenda.
- Add to the Inbox from Shortcuts and Siri, in English or Danish.
- Changes made elsewhere arrive while the app is open.

### Browser extension

#### Added

- An extension for Firefox and Chromium-based browsers that adds the current page to the Inbox: its title, its address, and any selected text.

### Thunderbird extension

#### Added

- An extension that adds a mail message to the Inbox.

