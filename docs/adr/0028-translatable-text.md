# 0028. Translatable text

## Status

Accepted

## Context

The interface is English, written as literal strings in HEEx and
LiveViews. Phoenix set up Gettext (`MarskalWeb.Gettext`), but only its
generated components use it. Translating later means finding every
literal; the longer that waits, the more there are. Dates and times
already follow a locale preference (ADR 0027).

## Decision

- New and changed text the user reads goes through **Gettext**:
  `gettext/1,2` in components and LiveViews, `ngettext/3,4` where a count
  picks the form, and `dgettext("errors", …)` for validation messages.
  Existing literals move to Gettext when the code around them changes.
- A message is a whole sentence or label, with `%{name}` for what goes
  in it. Sentences are not built from pieces, since word order differs
  between languages.
- Not translated: what the user typed or stored (titles, notes, tag
  names, including tags an import creates), log messages, sync and API
  error codes, and anything a machine reads.
- Domain code (`Marskal`) does not call Gettext. Its changeset messages
  are plain English, translated in the web layer by `translate_error/1`.
- The templates in `priv/gettext/*.pot` are generated: `mix precommit`
  extracts them, and `mix ci` fails when they are out of date. They have
  no line numbers and are sorted, so moving code does not change them.
- Gettext's locale stays `en` until there is a translation. Then the
  language comes from the locale preference (ADR 0027): its list gains
  locales in that language, and the language part sets Gettext's locale.

## Consequences

- Each new string costs a function call; translating later costs only
  the `.po` files.
- Nothing checks that a literal was missed. Review does, until a check
  for literals in templates is worth writing.
