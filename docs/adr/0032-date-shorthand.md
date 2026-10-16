# 0032. Typed dates and the calendar

## Status

Accepted

Changes how Defer, Planned, and Due ([ADR 0006](0006-task-defer-planned-due.md))
are entered in the web app. What is stored is unchanged.

## Context

Each date was a pair of browser inputs, a day and a time. Picking "next
Friday" meant opening the browser's calendar, which starts its week where
the browser likes, not on the user's `week_start` (ADR 0023), and setting a
time took a second input. People who plan by keyboard type dates: "tom",
"fri", "1w".

The terminal client (ADR 0020) takes dates as arguments, where the same
shorthand fits, and will read it with the Rust library (ADR 0018).

Alternatives considered:

- **A natural-language library.** Rejected. The ones for Elixir are thin,
  English only, and none has a Rust twin that reads the same way. The
  grammar is small enough to own.
- **Reading in the browser.** Rejected. The preview would need the user's
  zone, week start, and locale order in TypeScript, and the server would
  still have to read the text it is sent.
- **The browser's date picker for the calendar.** Rejected. It ignores the
  week start and the locale's month names, and looks different everywhere.

## Decision

**One text field per date.** It shows the stored day in the locale's
medium form ("16 Oct 2026", "Oct 16, 2026"), with the time when it is not
the field's default. That label reads back as the same day.

**`Marskal.DateInput.parse/3`** reads the text. It is pure: the caller passes
now on the user's wall clock, the week start, and the locale's numeric order
(day-month-year, month-day-year, or year-month-day). It gives a day and an
optional time, blank, or an error. English and Danish words are read
whatever the locale; case and Unicode normalisation do not matter.

| Typed | Means |
|-------|-------|
| `today` `tod` `i dag`, `tomorrow` `tom` `i morgen`, `yesterday` `i går`, `overmorgen` | That day |
| `now` `nu` | Today at this minute |
| `mon` … `sun`, `man` … `søn`, full names | The next one after today; on that weekday, a week on |
| `next fri`, `næste fre` | That weekday in next week, by the week start |
| `next week` / `month` / `year` | The first day of it |
| `3d` `1w` `2m` `1y` `+3d` `-1d` `2 weeks` `in 3 days` `om 2 uger` | Days, weeks, months, years on; a month on from the 31st clamps |
| `3h` `90 min` `2t` | Hours or minutes on from now, with that time |
| `24/12` `24.12` `24-12`, `24/12/27` | By the locale's order; without a year, the next one from today |
| `2026-12-24` | Year, month, day, in any locale |
| `24`, `24.`, `3rd` | The next day with that day of the month |
| `24 dec`, `dec 24`, `24. december 2027` | English or Danish month names |
| `fri 23 oct` | The weekday must be that day's, or it is an error |
| `14:00`, `2pm`, `2:30 pm`, `kl 9`, `at 9`, `@9` | A time, at the end or the start; alone, today |
| `fri 14.30` | A dotted time only after a day; alone, `24.12` is a date |

`m` is a month; minutes are `min`. A bare number after a day is a day of
the month, not an hour: `tom 9` is an error, `tom kl 9` is not. A day with
no time takes the field's default time, as before.

**The vectors** in `sync/fixtures/date_input.json` are generated from
`Marskal.DateInput`. The Rust library runs them when it reads dates.

**In the inspector:**

- As the text changes, the field shows what it reads ("Friday, 23 October,
  17:00") or that it cannot. Nothing is saved while typing.
- Enter or leaving the field saves it. Text that cannot be read is not
  saved; the stored value stays and the message stays until the text is
  fixed or reverted with Escape. Clearing the text clears the date.
- A calendar button beside each field opens a month grid, rendered by the
  server, starting on the user's week start, with today, the stored day,
  and the month's name in the user's locale. Picking a day keeps the stored
  time. The grid moves by month, closes on Escape, and is reached by
  keyboard.
- Defer indefinitely stays a checkbox.

## Consequences

- Dates are entered by keyboard, and the calendar starts its weeks where
  the user's do.
- The grammar is a contract between the server and the Rust library; a
  change to it is a change to the vectors.
- Words in other languages need a table in both places. The words are not
  translated through Gettext (ADR 0028): what is read does not follow the
  interface language.
- Tests: the vectors; that a label reads back to its day; that typing does
  not save and an unreadable value is not saved; the calendar's week start.
