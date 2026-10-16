# 0027. Locale for dates and times

## Status

Accepted

Amended by [ADR 0032](0032-date-shorthand.md): a `da` locale writes
Danish month and weekday names, and typed dates read its words.

## Context

Dates and times were formatted with fixed `strftime` patterns: "11 Oct",
"16:30". People read dates in their region's way: the order of day and
month, a 12- or 24-hour clock, the separator in a time. The interface is
English, so a date in another language would sit oddly beside it.

The browser's `Intl` API could format in the browser's locale, but a
browser's language list rarely says what a user wants: someone may read
English and want Danish conventions (`en-DK`) without that being among
their `Accept-Language` entries. Due notifications (ADR 0006) will also be
formatted where there is no browser.

## Decision

- **ex_cldr** formats dates and times on the server (`Marskal.Cldr`,
  `Marskal.DateFormat`). It brings CLDR data for plurals, lists, numbers,
  and calendars when those are needed.
- The locale is an explicit **preference**, `user_preferences.locale`
  (ADR 0023), default **`en-150`** (English, European conventions, the
  formats used before). It syncs and a client may patch it.
- The choices are **English locales** whose region sets the conventions,
  such as `en-DK`, `en-GB`, `en-SE`, and `en` for the United States. The
  words stay English while the interface is. A translated interface would
  add other languages to the same list.
- A LiveView or request sets the process locale from the preference, and
  `Marskal.DateFormat` reads it. Code without a request passes the locale.
- Form inputs keep ISO values; the browser shows `type="date"` and
  `type="time"` in its own locale.
- **Locale data** is not committed. ex_cldr downloads it at compile time
  in development. The Nix build, which has no network, fetches each file
  by a hash in `web/nix/cldr-locales.nix`, written by
  `web/nix/update-cldr-locales`; a test fails when that list and
  `Marskal.Cldr` disagree.

## Consequences

- Adding a locale is a line in `Marskal.Cldr`, a region name, and a run of
  `nix/update-cldr-locales`. So is upgrading ex_cldr.
- Every format goes through `Marskal.DateFormat`, using CLDR skeletons
  (`MMMd`, `yMMMd`, `jm`) rather than the locale's short formats, some of
  which are not usable in every locale.
- The offline client library's local schema gains the column.
