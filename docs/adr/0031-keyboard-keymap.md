# 0031. Keyboard keymap

## Status

Accepted

## Context

Task lists already move with the keyboard: arrow keys change the focused
row, Tab and the bracket keys indent, and Alt-arrow keys reorder siblings
(ADR 0009). Those keys are what someone expects from a list. A Vim-style
map is wanted as well, and it should not be the one a new account gets.

The choice is a preference, so it belongs on `user_preferences` and syncs
with the others (ADR 0023). The names are on the wire, and the two maps
are the product, so they are recorded here.

## Decision

- One preference, **`keymap`**, with values **`standard`** (the default)
  and **`vim`**, shown as "Vim-style", like the legendary text editor, where
  instead of complicated chords with modifier keys, the plain keys are used
  as shortcuts.
  The preference is a typed column with a check, a client may patch it, and
  a client that already pulled asks for a snapshot.
- Row keys apply while focus is on a task row, and not while it is in a
  text field or an open dialog. What Vim would call insert mode happens when
  a text field has focus. Arrow keys, Space, Delete, the outline keys, and
  the letters `f` and `n` work in both maps. Vim-style adds more letters.
- Movement works on every task list. Indent, outdent, and reordering stay
  on an outline. Collapse and expand stay where a row has subtasks: Left
  and `h` collapse an open row, Right and `l` expand a collapsed one.
- **Check** does what the checkbox does: a To-Do task becomes Done, and
  any other state becomes To-Do. **Drop** sets Dropped and says so in a
  flash, since it needs no confirmation. **Flag** toggles the task's own
  flag, not a flag inherited from its project (ADR 0025). **New** focuses
  the page's add field, or the inbox capture when the page has none. A
  title is required, so the key does not insert a blank task.
- Getting to the list takes no mouse. With nothing focused, Down (and `j`
  in Vim-style) focuses the row last focused, or the first. Escape in a task add
  field does the same.
- `?` opens a reference of the keys, for the user's map, on any page.

| Action | Standard | Vim-style, as well |
|---|---|---|
| Previous and next row | Up, Down | `k`, `j` |
| First and last row | Home, End | `gg`, `G` |
| Collapse and expand | Left, Right | `h`, `l` |
| Indent and outdent | Tab, Shift-Tab, Cmd-], Cmd-[ | `>`, `<` |
| Move among siblings | Alt-Up, Alt-Down | `K`, `J` |
| Check | Space | `x` |
| Drop | Delete, Backspace | `dd` |
| Flag | `f` | |
| New task | `n` | `o` |
| Go to the list | Down, or Escape in an add field | `j` |
| Show the keys | `?` | |

Cmd-] and Cmd-[ are Ctrl-] and Ctrl-[ off a Mac, as before. Enter still
opens the focused row. Escape still closes the inspector and the phone
navigation.

## Consequences

- A task that the key resolves stays on the list until the user leaves the
  view, as a click on the checkbox does, so the same key can reopen it.
  That is the undo for Drop.
- `gg` and `dd` are the only two-key sequences, and a sequence waits one
  second. Another key after the first does that key's own action, so a
  single `d` does nothing.
- Down on a page with nothing focused moves to the list instead of
  scrolling. Once a row has focus, the page scrolls with it.
- The terminal UI and the iOS app can read the same preference. This ADR
  does not bind keys there.
