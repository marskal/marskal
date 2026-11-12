defmodule MarskalWeb.GoTo do
  @moduledoc """
  Go to a view, folder, project, or tag by typing part of its name
  (ADR 0033). Cmd-K or Ctrl-K, or `/`, opens it from any page, and so does
  the button in the header. The targets load when it opens; each key
  matches them in memory, with no query.
  """

  use MarskalWeb, :live_component

  alias Marskal.GoTo
  alias Marskal.GoTo.Target

  @impl true
  def mount(socket) do
    {:ok, assign(socket, targets: [], query: "", results: views())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="go-to" phx-hook=".GoTo" phx-target={@myself}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.go-to) {
          dialog {
            width: min(100% - 2rem, 36rem);
            max-height: min(100% - 4rem, 32rem);
            margin: 4rem auto auto;
            padding: 0;
            border: 1px solid var(--border);
            border-radius: 12px;
            background: var(--surface);
            color: var(--text);
          }

          dialog[open] {
            display: flex;
            flex-direction: column;
          }

          dialog::backdrop {
            background: var(--scrim);
          }

          form {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            padding: 0.5rem 0.75rem;
            border-bottom: 1px solid var(--border);
          }

          form .icon {
            flex-shrink: 0;
            color: var(--muted);
          }

          input {
            flex: 1;
            min-width: 0;
            padding: 0.5rem 0;
            border: 0;
            background: transparent;
            color: inherit;
            font: inherit;
            font-size: 1.0625rem;
          }

          input:focus {
            outline: none;
          }

          ul {
            margin: 0;
            padding: 0.375rem;
            overflow-y: auto;
            list-style: none;
          }

          a {
            display: flex;
            align-items: center;
            gap: 0.5rem;
            min-height: 2.5rem;
            padding: 0.25rem 0.625rem;
            border-radius: var(--radius);
            color: var(--text);
            text-decoration: none;
          }

          a > .icon {
            flex-shrink: 0;
            color: var(--muted);
          }

          [aria-selected="true"] > a {
            background: var(--accent-tint-strong);
          }

          .path {
            display: inline-flex;
            flex-wrap: wrap;
            align-items: baseline;
            gap: 0 0.3em;
            min-width: 0;
          }

          .ancestor,
          .sep,
          .state {
            color: var(--muted);
          }

          .is-hidden .name {
            color: var(--muted);
          }

          .state {
            margin-left: auto;
            font-size: 0.875em;
          }

          .empty {
            margin: 0;
            padding: 1rem;
            color: var(--muted);
          }

          @media (max-width: 720px) {
            dialog {
              margin-top: 1rem;
            }
          }
        }
      </style>
      <dialog
        id={"#{@id}-dialog"}
        aria-label={gettext("Go to")}
        phx-mounted={JS.ignore_attributes("open")}
      >
        <form id={"#{@id}-form"} phx-change="query" phx-target={@myself}>
          <Lucideicons.search class="icon" />
          <input
            type="text"
            id={"#{@id}-query"}
            name="query"
            value={@query}
            placeholder={gettext("Go to a view, project, folder, or tag")}
            aria-label={gettext("Go to")}
            role="combobox"
            aria-expanded="true"
            aria-controls={"#{@id}-results"}
            aria-autocomplete="list"
            autocomplete="off"
            autocapitalize="off"
            spellcheck="false"
            enterkeyhint="go"
          />
        </form>
        <ul id={"#{@id}-results"} role="listbox" aria-label={gettext("Places")}>
          <li
            :for={target <- @results}
            id={"#{@id}-#{target.type}-#{target.id}"}
            role="option"
            class={target.hidden && "is-hidden"}
          >
            <.link navigate={path(target)} tabindex="-1" data-opens-inspector={target.type != :view}>
              <.target_icon target={target} />
              <span class="path">
                <%= for segment <- Enum.drop(target.path, -1) do %>
                  <span class="ancestor">{segment}</span>
                  <span class="sep" aria-hidden="true">›</span>
                <% end %>
                <span class="name">{List.last(target.path)}</span>
              </span>
              <span :if={label = state_label(target)} class="state">{label}</span>
            </.link>
          </li>
        </ul>
        <p :if={@results == []} class="empty">{gettext("Nothing matches.")}</p>
      </dialog>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".GoTo" extension="ts">
        import {ViewHook} from "phoenix_live_view"

        function typing(target: EventTarget | null): boolean {
          return target instanceof HTMLElement &&
            Boolean(target.closest("input, textarea, select, [contenteditable]:not([contenteditable='false'])"))
        }

        // The dialog is a combobox: focus stays in the field, and the arrow
        // keys move the selected option, which Enter follows.
        export default class extends ViewHook {
          active: string | null = null

          get dialog() { return this.el.querySelector<HTMLDialogElement>("dialog")! }
          get input() { return this.el.querySelector<HTMLInputElement>("input")! }
          get options() { return Array.from(this.el.querySelectorAll<HTMLElement>("[role=option]")) }

          onDocumentKeydown = (event: KeyboardEvent) => {
            if (event.defaultPrevented || event.altKey || event.shiftKey) return
            const chord = (event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k"
            const slash = event.key === "/" && !event.metaKey && !event.ctrlKey && !typing(event.target)
            if (!chord && !(slash && !document.querySelector("dialog[open]"))) return
            event.preventDefault()
            if (this.dialog.open) this.input.select()
            else this.open()
          }

          onDocumentClick = (event: MouseEvent) => {
            if (event.target instanceof Element && event.target.closest("[data-go-to]")) this.open()
          }

          onKeydown = (event: KeyboardEvent) => {
            if (event.key === "ArrowDown" || event.key === "ArrowUp") {
              event.preventDefault()
              const options = this.options
              const index = options.findIndex((option) => option.id === this.active)
              const step = event.key === "ArrowDown" ? 1 : -1
              const next = options[(index + step + options.length) % options.length]
              if (next) this.select(next)
            } else if (event.key === "Enter") {
              event.preventDefault()
              const option = this.active ? document.getElementById(this.active) : null
              option?.querySelector("a")?.click()
            }
          }

          // A click on the backdrop targets the dialog itself.
          onClick = (event: MouseEvent) => {
            const target = event.target as Element
            if (target.closest("a")) this.dialog.close()
            else if (target === this.dialog && this.outside(event)) this.dialog.close()
          }

          onPointerMove = (event: PointerEvent) => {
            const option = (event.target as Element).closest<HTMLElement>("[role=option]")
            if (option && option.id !== this.active) this.select(option)
          }

          mounted() {
            document.addEventListener("keydown", this.onDocumentKeydown)
            document.addEventListener("click", this.onDocumentClick)
            this.input.addEventListener("keydown", this.onKeydown)
            this.dialog.addEventListener("click", this.onClick)
            this.dialog.addEventListener("pointermove", this.onPointerMove)
            this.el.querySelector("form")!.addEventListener("submit", (event) => event.preventDefault())
            this.select(this.options[0] ?? null)
          }

          // New results keep the selected option if it is still there.
          updated() {
            const options = this.options
            this.select(options.find((option) => option.id === this.active) ?? options[0] ?? null)
          }

          destroyed() {
            document.removeEventListener("keydown", this.onDocumentKeydown)
            document.removeEventListener("click", this.onDocumentClick)
          }

          open() {
            this.input.value = ""
            this.active = null
            this.pushEventTo(this.el, "open", {})
            this.dialog.showModal()
            this.input.focus()
          }

          select(option: HTMLElement | null) {
            this.active = option?.id ?? null
            for (const each of this.options) each.setAttribute("aria-selected", String(each === option))
            if (option) {
              this.input.setAttribute("aria-activedescendant", option.id)
              option.scrollIntoView({block: "nearest"})
            } else {
              this.input.removeAttribute("aria-activedescendant")
            }
          }

          outside(event: MouseEvent): boolean {
            const box = this.dialog.getBoundingClientRect()
            return event.clientX < box.left || event.clientX > box.right ||
              event.clientY < box.top || event.clientY > box.bottom
          }
        }
      </script>
    </div>
    """
  end

  @impl true
  def handle_event("open", _params, socket) do
    %{user: user, nav: nav} = socket.assigns

    {:noreply,
     assign(socket, targets: views() ++ GoTo.targets(user, nav), query: "", results: views())}
  end

  def handle_event("query", %{"query" => query}, socket) do
    results =
      if String.trim(query) == "",
        do: views(),
        else: GoTo.run(socket.assigns.targets, query)

    {:noreply, assign(socket, query: query, results: results)}
  end

  @doc "The header's button that opens the dialog."
  def button(assigns) do
    ~H"""
    <button type="button" class="go-to-button" data-go-to title={gettext("Go to")}>
      <style :type={MarskalWeb.ColocatedCSS}>
        @scope (.go-to-button) {
          :scope {
            display: inline-flex;
            align-items: center;
            gap: 0.5rem;
            min-width: 12rem;
            padding: 0.25rem 0.375rem 0.25rem 0.625rem;
            border: 1px solid var(--border);
            border-radius: var(--radius);
            background: var(--bg);
            color: var(--muted);
            font: inherit;
          }

          :scope:hover {
            color: var(--text);
          }

          kbd {
            margin-left: auto;
            padding: 0 0.4em;
            border: 1px solid var(--border);
            border-radius: 0.3em;
            font: inherit;
            font-size: 0.875em;
          }

          @media (max-width: 720px) {
            :scope {
              justify-content: center;
              min-width: 0;
              width: 2.75rem;
              height: 2.75rem;
              margin: -0.25rem 0;
              padding: 0;
              border: 0;
              background: transparent;
              color: var(--text);
            }

            .label,
            kbd {
              display: none;
            }
          }
        }
      </style>
      <Lucideicons.search class="icon" />
      <span class="label">{gettext("Go to…")}</span>
      <kbd aria-hidden="true">/</kbd>
    </button>
    """
  end

  attr :target, Target, required: true

  defp target_icon(%{target: %{type: :view, id: :inbox}} = assigns),
    do: ~H|<Lucideicons.inbox class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :open}} = assigns),
    do: ~H|<Lucideicons.list class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :agenda}} = assigns),
    do: ~H|<Lucideicons.calendar_days class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :flagged}} = assigns),
    do: ~H|<Lucideicons.flag class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :review}} = assigns),
    do: ~H|<Lucideicons.coffee class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :untagged}} = assigns),
    do: ~H|<Lucideicons.tag class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :import}} = assigns),
    do: ~H|<Lucideicons.download class="icon" />|

  defp target_icon(%{target: %{type: :view, id: :settings}} = assigns),
    do: ~H|<Lucideicons.settings class="icon" />|

  defp target_icon(%{target: %{type: :folder}} = assigns),
    do: ~H|<Lucideicons.folder class="icon" />|

  defp target_icon(%{target: %{type: :tag}} = assigns),
    do: ~H|<Lucideicons.tag class="icon" />|

  defp target_icon(%{target: %{state: :done}} = assigns),
    do: ~H|<Lucideicons.circle_check_big class="icon" />|

  defp target_icon(%{target: %{state: :dropped}} = assigns),
    do: ~H|<Lucideicons.circle_off class="icon" />|

  defp target_icon(assigns), do: ~H|<Lucideicons.circle class="icon" />|

  # A resolved target says so; a deferred one, or one in a dropped folder,
  # is only dimmed.
  defp state_label(%Target{hidden: false}), do: nil
  defp state_label(%Target{state: :done}), do: gettext("Done")
  defp state_label(%Target{state: :dropped}), do: gettext("Dropped")
  defp state_label(%Target{}), do: nil

  defp path(%Target{type: :view, id: :inbox}), do: ~p"/inbox"
  defp path(%Target{type: :view, id: :open}), do: ~p"/open"
  defp path(%Target{type: :view, id: :agenda}), do: ~p"/agenda"
  defp path(%Target{type: :view, id: :flagged}), do: ~p"/flagged"
  defp path(%Target{type: :view, id: :review}), do: ~p"/review"
  defp path(%Target{type: :view, id: :untagged}), do: ~p"/tags/untagged"
  defp path(%Target{type: :view, id: :import}), do: ~p"/imports"
  defp path(%Target{type: :view, id: :settings}), do: ~p"/users/settings"
  defp path(%Target{type: type, id: id}), do: MarskalWeb.NavComponents.record_path(type, id)

  defp views do
    [
      {:inbox, gettext("Inbox")},
      {:open, gettext("Open")},
      {:agenda, gettext("Agenda")},
      {:flagged, gettext("Flagged")},
      {:review, gettext("Review")},
      {:untagged, gettext("Untagged")},
      {:import, gettext("Import")},
      {:settings, gettext("Settings")}
    ]
    |> Enum.map(fn {id, name} -> %Target{type: :view, id: id, path: [name]} end)
  end
end
