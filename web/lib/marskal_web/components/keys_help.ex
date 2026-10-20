defmodule MarskalWeb.KeysHelp do
  @moduledoc """
  The keyboard reference that `?` opens (ADR 0031), and the keys that work
  with no task row focused: Down (or `j`) goes to the list, and Escape in a
  task add field goes back to it. The row keys are the `.Outline` hook's.
  """

  use MarskalWeb, :html

  attr :keymap, :atom, required: true

  def dialog(assigns) do
    # An action only Vim-style has, such as New task above, is left out of
    # the standard map's list.
    rows =
      if assigns.keymap == :vim,
        do: rows(),
        else: Enum.reject(rows(), fn {_action, keys, _vim} -> keys == [] end)

    assigns = assign(assigns, :rows, rows)

    ~H"""
    <dialog
      id="keys-help"
      class={["keys-help", @keymap == :vim && "has-vim"]}
      aria-labelledby="keys-help-heading"
      phx-hook=".Keys"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.keys-help) {
          /* The type grows with the window, so the table stays readable on a
             large monitor; sizes below are in em to follow it. */
          :scope {
            width: min(100% - 2rem, 36em);
            max-height: calc(100% - 2rem);
            padding: 1em 1.25em 1.25em;
            font-size: clamp(0.875rem, 0.5rem + 0.6vw, 1.25rem);
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--surface);
            color: var(--text);
          }

          /* Room for the third column. */
          :scope.has-vim {
            width: min(100% - 2rem, 46em);
          }

          :scope::backdrop {
            background: var(--scrim);
          }

          h2 {
            margin: 0 0 0.75em;
            font-size: 1.15em;
          }

          .close {
            position: absolute;
            top: 0.5rem;
            right: 0.5rem;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            width: 2.75rem;
            height: 2.75rem;
            padding: 0;
            border: 0;
            background: transparent;
            color: var(--muted);
          }

          table {
            width: 100%;
            border-collapse: collapse;
            font-size: 1em;
          }

          th,
          td {
            padding: 0.3em 0.75em 0.3em 0;
            text-align: left;
            vertical-align: middle;
          }

          thead th {
            color: var(--muted);
            font-weight: 500;
          }

          .keys {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: center;
            gap: 0.4em 0.6em;
          }

          /* A chord or a sequence: its keys, close together. */
          .keys > kbd:has(kbd) {
            display: inline-flex;
            align-items: center;
            gap: 0.2em;
            font: inherit;
          }

          .plus {
            color: var(--muted);
            font-size: 0.85em;
          }

          /* A keycap: a lighter top face over a deeper bottom edge. */
          kbd kbd,
          .keys > kbd:not(:has(kbd)) {
            display: inline-block;
            min-width: 1.9em;
            padding: 0.1em 0.45em 0.2em;
            border: 1px solid var(--border-strong);
            border-radius: 0.35em;
            background: linear-gradient(
              var(--surface),
              color-mix(in oklch, var(--surface), var(--text) 6%)
            );
            box-shadow:
              inset 0 -0.18em 0 color-mix(in oklch, var(--surface), var(--text) 12%),
              0 1px 1px var(--shadow);
            color: var(--text);
            font: inherit;
            font-size: 0.9em;
            line-height: 1.3;
            text-align: center;
          }

          p {
            margin: 0.75em 0 0;
            color: var(--muted);
            font-size: 0.9em;
          }
        }
      </style>
      <form method="dialog">
        <button type="submit" class="close" aria-label={gettext("Close")}>
          <Lucideicons.x class="icon" />
        </button>
      </form>
      <h2 id="keys-help-heading">{gettext("Keyboard shortcuts")}</h2>
      <table>
        <thead>
          <tr>
            <th scope="col">{gettext("Action")}</th>
            <th scope="col">{gettext("Keys")}</th>
            <th :if={@keymap == :vim} scope="col">{gettext("Vim-style")}</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={{action, keys, vim} <- @rows}>
            <th scope="row">{action}</th>
            <td><.keys keys={keys} /></td>
            <td :if={@keymap == :vim}><.keys keys={vim} /></td>
          </tr>
        </tbody>
      </table>
      <p>
        {gettext(
          "Keys act on the focused task, folder, project, or tag, not while you type. Off a Mac, Cmd is Ctrl."
        )}
      </p>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Keys" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // A task row's title, or a folder, project, or tag row's link.
      const rowTitle = ".app-main .task-row button.select, .app-main .nav-row [data-nav-stop]"
      const rowStop = "button.select, [data-nav-stop]"

      function typing(target: EventTarget | null): boolean {
        return target instanceof HTMLElement &&
          Boolean(target.closest("input, textarea, select, [contenteditable]:not([contenteditable='false'])"))
      }

      const plain = (event: KeyboardEvent) => !event.metaKey && !event.ctrlKey && !event.altKey

      export default class extends ViewHook<HTMLDialogElement> {
        lastRow: string | null = null

        // The selected row, else the row last focused, else the first.
        focusList(): boolean {
          const last = this.lastRow && document.getElementById(this.lastRow)
          const title =
            document.querySelector<HTMLElement>(".app-main .task-row.is-selected button.select") ||
            (last instanceof HTMLElement && last.querySelector<HTMLElement>(rowStop)) ||
            document.querySelector<HTMLElement>(rowTitle)
          if (!title) return false
          title.focus()
          return true
        }

        onFocusIn = (event: FocusEvent) => {
          if (!(event.target instanceof HTMLElement)) return
          const row = event.target.closest<HTMLElement>(".app-main .task-row, .app-main .nav-row")
          if (row?.id && event.target.matches(rowStop)) this.lastRow = row.id
        }

        onKeydown = (event: KeyboardEvent) => {
          if (event.defaultPrevented || document.querySelector("dialog[open]")) return

          if (event.key === "Escape" && event.target instanceof HTMLElement && event.target.closest("[data-new-task]")) {
            if (this.focusList()) event.preventDefault()
            return
          }

          if (typing(event.target) || !plain(event)) return

          if (event.key === "?") {
            event.preventDefault()
            this.el.showModal()
            return
          }

          // Nothing focused: the first key that moves goes to the list.
          const idle = document.activeElement === null || document.activeElement === document.body
          const vim = document.getElementById("app-shell")?.dataset.keymap === "vim"
          const moves = event.key === "ArrowDown" || (vim && event.key === "j")
          if (idle && moves && this.focusList()) event.preventDefault()
        }

        // Right in the sidebar, with nothing to expand, comes back here.
        onFocusList = () => this.focusList()

        mounted() {
          document.addEventListener("keydown", this.onKeydown)
          document.addEventListener("focusin", this.onFocusIn)
          window.addEventListener("marskal:focus-list", this.onFocusList)
        }

        destroyed() {
          document.removeEventListener("keydown", this.onKeydown)
          document.removeEventListener("focusin", this.onFocusIn)
          window.removeEventListener("marskal:focus-list", this.onFocusList)
        }
      }
    </script>
    """
  end

  attr :keys, :list, required: true

  # Each entry is a key, {:chord, keys} held together, or {:seq, keys}
  # pressed in turn.
  defp keys(assigns) do
    ~H"""
    <span :if={@keys != []} class="keys">
      <%= for key <- @keys do %>
        <%= case key do %>
          <% {:chord, parts} -> %>
            <kbd>
              <%= for {part, index} <- Enum.with_index(parts) do %>
                <span :if={index > 0} class="plus" aria-hidden="true">+</span><kbd>{part}</kbd>
              <% end %>
            </kbd>
          <% {:seq, parts} -> %>
            <kbd><kbd :for={part <- parts}>{part}</kbd></kbd>
          <% key -> %>
            <kbd>{key}</kbd>
        <% end %>
      <% end %>
    </span>
    """
  end

  # {action, keys in both maps, keys Vim adds}
  defp rows do
    [
      {gettext("Previous and next row"), ["↑", "↓"], ["k", "j"]},
      {gettext("First and last row"), [gettext("Home"), gettext("End")],
       [{:seq, ["g", "g"]}, "G"]},
      {gettext("Collapse and expand"), ["←", "→"], ["h", "l"]},
      {gettext("Indent and outdent"),
       [
         gettext("Tab"),
         {:chord, [gettext("Shift"), gettext("Tab")]},
         {:chord, ["Cmd", "]"]},
         {:chord, ["Cmd", "["]}
       ], [">", "<", "L", "H"]},
      {gettext("Move among siblings"), [{:chord, ["Alt", "↑"]}, {:chord, ["Alt", "↓"]}],
       ["K", "J"]},
      {gettext("Complete or reopen"), [gettext("Space")], ["x"]},
      {gettext("Drop"), [gettext("Delete")], [{:seq, ["d", "d"]}]},
      {gettext("Flag"), ["f"], []},
      {gettext("New task below"), ["n"], ["o"]},
      {gettext("New task above"), [], ["O"]},
      {gettext("Edit in the inspector"), [gettext("Enter")], []},
      {gettext("Go to the list"), ["↓", gettext("Esc")], ["j"]},
      {gettext("Go to the sidebar, from a top row"), ["←"], ["h"]},
      {gettext("Back from the sidebar"), ["→"], ["l"]},
      {gettext("Show this help"), ["?"], []}
    ]
  end
end
