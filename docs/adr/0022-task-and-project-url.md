# 0022. A URL on tasks and projects

## Status

Accepted

## Context

Much work points at one thing somewhere else: a page to read, a file to
edit, a ticket to solve. Imported titles sometimes carry that link as
Markdown, which reads badly as a title, and titles are plain text
everywhere they show.

## Decision

- Tasks and projects get one optional **`url`**. Titles stay plain text;
  notes stay Markdown and may hold any number of further links.
- A URL is absolute: a scheme, a colon, then no whitespace, at most 2048
  characters. Any scheme is fine (`https:`, `file:`, `mailto:`, an app's
  own), except `javascript:`, `data:`, and `vbscript:`, which run or render
  content in the page that shows them. The database checks the shape and
  the length; the changeset also refuses those schemes. Surrounding
  whitespace is trimmed, and a blank value clears the field.
- The URL syncs as an ordinary field, writable by clients (ADR 0014,
  ADR 0019).
- A recurring occurrence copies it with the title (ADR 0007).
- **Import:** a link in a source title moves to `url`, and the title keeps
  the link text. If a title holds more than one link, the first becomes the
  URL and the rest go to the notes.
- Views show the URL as a link beside the title, opening in a new tab.

## Consequences

- Browsers do not follow `file:` links from a web page. The web app still
  shows them, so they can be copied; a local client can open them.
- One URL per item. Several links belong in the notes, or in subtasks with a
  URL each.
- The client library's local schema gains the column, and a client asks for
  a snapshot after upgrading so it learns the URLs it already pulled.
