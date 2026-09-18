# 0012. ViewComponent widgets with CSS `@scope`

## Status

Accepted

## Context

Marskal is server-rendered Hotwire (ERB, Stimulus, importmap, no Node). The
view layer started as pages plus partials and one global stylesheet. Upcoming
UI (outliner, date fields, dialogs, nested tags) needs reusable widgets with a
real Ruby API, not a React/SPA kit and not Tailwind.

ViewComponent is the least disruptive step up from partials: ERB stays, slots
and initializer contracts exist, and v4 is LTS. Phlex (HTML-as-Ruby) was
rejected because markup should stay visible HTML next to plain CSS.

ViewComponent does not load or isolate CSS. Propshaft’s `stylesheet_link_tag
:app` only picks up `app/assets/**/*.css`. Putting `app/components` on the
asset path would also publish `.rb` / `.erb` into `public/assets`.

## Decision

- **Pages stay ERB.** Inbox, streams, project show, layouts, and the sidebar
  remain templates/partials.
- **Reusable widgets are ViewComponents** under `app/components/`, subclassing
  `ApplicationComponent`.
- **No Tailwind, no UI kit** (Poetry, daisyUI, RubyUI, …). Tokens stay CSS
  custom properties on `:root`.
- **Isolation is CSS `@scope`**, not BEM prefixes or a bundler. Each widget
  has a root class (`ApplicationComponent.scope_class`) and a stylesheet:

  `app/assets/stylesheets/components/<scope-class>.css`

  ```css
  @scope (.task-row) {
    :scope { /* root */ }
    .title { /* descendant; does not leak */ }
  }
  ```

- **Form controls that must stay helpers** (`button_to`, `form.submit`) use
  `ButtonComponent.classes(...)` / the `btn` helper rather than wrapping the
  helper in a component.

## Consequences

- New chrome (button, dialog, combobox, date field, task row) lands as a
  component + `@scope` sheet, not more rules in `application.css`.
- `application.css` keeps tokens, reset, and app shell (header, sidebar,
  page frame).
- Outliner interaction is still custom Stimulus; the component layer only
  packages pieces.
- Browsers that ignore `@scope` drop the block (unstyled widget, no leak).
  Acceptable for this app.
