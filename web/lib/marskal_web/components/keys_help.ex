defmodule MarskalWeb.KeysHelp do
  @moduledoc """
  The keyboard reference that `?` opens (ADR 0031), and the keys that work
  with no task row focused: Down (or `j`) goes to the list, and Escape in a
  task add field goes back to it. The row keys are the `.Outline` hook's.
  """

  use MarskalWeb, :html

  attr :keymap, :atom, required: true

  def dialog(assigns) do
    assigns = assign(assigns, :rows, rows())

    ~H"""
    <dialog
      id="keys-help"
      class="keys-help"
      aria-labelledby="keys-help-heading"
      phx-hook=".Keys"
      phx-mounted={JS.ignore_attributes("open")}
    >
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.keys-help) {
          :scope {
            width: min(100% - 2rem, 34rem);
            max-height: calc(100% - 2rem);
            padding: 1rem 1.25rem 1.25rem;
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--surface);
            color: var(--text);
          }

          :scope::backdrop {
            background: var(--scrim);
          }

          h2 {
            margin: 0 0 0.75rem;
            font-size: 1rem;
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
            font-size: 0.875rem;
          }

          th,
          td {
            padding: 0.3rem 0.5rem 0.3rem 0;
            text-align: left;
            vertical-align: top;
          }

          thead th {
            color: var(--muted);
            font-weight: 500;
          }

          kbd {
            display: inline-block;
            min-width: 1.5em;
            padding: 0 0.3em;
            border: 1px solid var(--border);
            border-radius: 4px;
            font: inherit;
            font-size: 0.8125rem;
            text-align: center;
          }

          p {
            margin: 0.75rem 0 0;
            color: var(--muted);
            font-size: 0.8125rem;
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
            <td>
              <span :for={{key, index} <- Enum.with_index(keys)}>
                {if index > 0, do: " "}<kbd>{key}</kbd>
              </span>
            </td>
            <td :if={@keymap == :vim}>
              <span :for={{key, index} <- Enum.with_index(vim)}>
                {if index > 0, do: " "}<kbd>{key}</kbd>
              </span>
            </td>
          </tr>
        </tbody>
      </table>
      <p>
        {gettext("Keys act on the focused task, not while you type. Off a Mac, Cmd is Ctrl.")}
      </p>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Keys" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      const rowTitle = ".app-main .task-row button.select"

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
            (last instanceof HTMLElement && last.querySelector<HTMLElement>("button.select")) ||
            document.querySelector<HTMLElement>(rowTitle)
          if (!title) return false
          title.focus()
          return true
        }

        onFocusIn = (event: FocusEvent) => {
          if (!(event.target instanceof HTMLElement)) return
          const row = event.target.closest<HTMLElement>(".task-row")
          if (row?.id && event.target.matches("button.select")) this.lastRow = row.id
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

        mounted() {
          document.addEventListener("keydown", this.onKeydown)
          document.addEventListener("focusin", this.onFocusIn)
        }

        destroyed() {
          document.removeEventListener("keydown", this.onKeydown)
          document.removeEventListener("focusin", this.onFocusIn)
        }
      }
    </script>
    """
  end

  # {action, keys in both maps, keys Vim adds}
  defp rows do
    [
      {gettext("Previous and next task"), ["↑", "↓"], ["k", "j"]},
      {gettext("First and last task"), [gettext("Home"), gettext("End")], ["gg", "G"]},
      {gettext("Collapse and expand"), ["←", "→"], ["h", "l"]},
      {gettext("Indent and outdent"), [gettext("Tab"), gettext("Shift-Tab"), "Cmd-]", "Cmd-["],
       [">", "<"]},
      {gettext("Move among siblings"), ["Alt-↑", "Alt-↓"], ["K", "J"]},
      {gettext("Complete or reopen"), [gettext("Space")], ["x"]},
      {gettext("Drop"), [gettext("Delete")], ["dd"]},
      {gettext("Flag"), ["f"], []},
      {gettext("New task below"), ["n"], ["o"]},
      {gettext("New task above"), [], ["O"]},
      {gettext("Edit in the inspector"), [gettext("Enter")], []},
      {gettext("Go to the list"), ["↓", gettext("Esc")], ["j"]},
      {gettext("Show this help"), ["?"], []}
    ]
  end
end
