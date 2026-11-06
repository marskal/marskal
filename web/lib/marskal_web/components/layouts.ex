defmodule MarskalWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use MarskalWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :current_nav, :atom, default: nil
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil

  attr :new_row, :any,
    default: nil,
    doc: "the inline new task, whose fields the inspector edits"

  attr :nav, :any, default: nil, doc: "the sidebar tree, assigned by MarskalWeb.Inspector"
  attr :change_version, :integer, default: 0

  attr :visibility, :list,
    default: nil,
    doc: "what this browser also shows (`MarskalWeb.Visibility`)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      id="app-shell"
      class={["app", (@inspector || @new_row) && "is-inspector-open"]}
      data-keymap={keymap(@current_scope)}
      phx-hook=".Inspector"
    >
      <header class="app-header">
        <button
          :if={@nav}
          type="button"
          class="app-header__menu"
          aria-label="Menu"
          aria-controls="sidebar"
          aria-expanded="false"
          phx-mounted={JS.ignore_attributes("aria-expanded")}
        >
          <Lucideicons.menu class="icon" />
        </button>
        <div class="app-header__brand">
          <.link navigate={MarskalWeb.UserAuth.signed_in_path(@current_scope)}>
            <img src={~p"/images/icon.svg"} alt="" class="app-header__logo" />
            <span>Marskal</span>
          </.link>
        </div>
        <MarskalWeb.GoTo.button :if={@nav} />
        <.visibility_toggle :if={@visibility} visibility={@visibility} />
        <.theme_toggle />
        <div class="app-header__account">
          <%= if @current_scope && @current_scope.user do %>
            <span class="who">{@current_scope.user.email}</span>
            <.link :if={@current_scope.user.superuser} href={~p"/dev/dashboard"}>Dashboard</.link>
            <.link href={~p"/users/settings"}>Settings</.link>
            <.link href={~p"/users/log-out"} method="delete">Log out</.link>
          <% else %>
            <.link href={~p"/users/log-in"}>Log in</.link>
            <.link href={~p"/users/register"}>Register</.link>
          <% end %>
        </div>
      </header>

      <div class={["app-body", @current_scope && @current_scope.user && "has-inspector"]}>
        <MarskalWeb.NavComponents.sidebar
          :if={@nav}
          nav={@nav}
          user={@current_scope.user}
          current_nav={@current_nav}
          current_id={@current_id}
          inspector={@inspector}
        />
        <div :if={@nav} class="sidebar-backdrop"></div>
        <div
          :if={@nav}
          id="sidebar-resizer"
          class="sidebar-resizer"
          role="separator"
          aria-orientation="vertical"
          aria-controls="sidebar"
          aria-label={gettext("Sidebar width")}
          tabindex="0"
          phx-hook=".SidebarResize"
          phx-mounted={JS.ignore_attributes(["aria-valuenow", "aria-valuemin", "aria-valuemax"])}
        >
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".SidebarResize" extension="ts">
          import {ViewHook} from "phoenix_live_view"

          // Drag the handle, or focus it and press the arrow keys, to set the
          // sidebar's width; a double click puts it back. The width is this
          // browser's, kept in localStorage; root.html.heex applies it before
          // the first paint. The CSS clamps it as the window narrows, too.
          const key = "marskal:sidebar-width"
          const root = document.documentElement
          const min = 192
          const max = () => Math.max(min, Math.min(640, window.innerWidth / 2))
          const clamp = (px: number) => Math.round(Math.min(max(), Math.max(min, px)))

          export default class extends ViewHook {
            onPointerDown = (event: PointerEvent) => {
              if (event.button !== 0) return
              event.preventDefault()
              this.el.setPointerCapture(event.pointerId)
              document.body.classList.add("is-resizing-sidebar")
            }

            onPointerMove = (event: PointerEvent) => {
              if (!this.el.hasPointerCapture(event.pointerId)) return
              const left = this.el.parentElement?.getBoundingClientRect().left ?? 0
              this.set(event.clientX - left)
            }

            onPointerEnd = () => {
              document.body.classList.remove("is-resizing-sidebar")
              this.save()
            }

            onKeydown = (event: KeyboardEvent) => {
              const steps: Record<string, number> = {ArrowLeft: -16, ArrowRight: 16}
              if (event.key in steps) this.set(this.width() + steps[event.key])
              else if (event.key === "Home") this.set(min)
              else if (event.key === "End") this.set(max())
              else return
              event.preventDefault()
              event.stopPropagation()
              this.save()
            }

            onDoubleClick = () => {
              root.style.removeProperty("--sidebar-width")
              try { localStorage.removeItem(key) } catch {}
              this.show()
            }

            mounted() {
              this.el.addEventListener("pointerdown", this.onPointerDown)
              this.el.addEventListener("pointermove", this.onPointerMove)
              this.el.addEventListener("lostpointercapture", this.onPointerEnd)
              this.el.addEventListener("keydown", this.onKeydown)
              this.el.addEventListener("dblclick", this.onDoubleClick)
              this.show()
            }

            width(): number {
              return document.getElementById("sidebar")?.getBoundingClientRect().width ?? 256
            }

            set(px: number) {
              root.style.setProperty("--sidebar-width", `${clamp(px)}px`)
              this.show()
            }

            show() {
              this.el.setAttribute("aria-valuemin", String(min))
              this.el.setAttribute("aria-valuemax", String(Math.round(max())))
              this.el.setAttribute("aria-valuenow", String(Math.round(this.width())))
            }

            save() {
              const width = root.style.getPropertyValue("--sidebar-width")
              try { if (width) localStorage.setItem(key, String(parseInt(width))) } catch {}
            }
          }
        </script>
        <div class="app-main-pane">
          <main class="app-main">
            {render_slot(@inner_block)}
          </main>
        </div>
        <div
          :if={@current_scope && @current_scope.user}
          class="app-inspector__backdrop"
          phx-click={if(@new_row, do: "inline-cancel", else: "close-inspector")}
        >
        </div>
        <aside
          :if={@current_scope && @current_scope.user}
          class="app-inspector"
          tabindex="-1"
          aria-label="Inspector"
        >
          <div class="app-inspector__chrome">
            <button
              type="button"
              class="app-inspector__close"
              phx-click={if(@new_row, do: "inline-cancel", else: "close-inspector")}
              aria-label={if(@new_row, do: gettext("Cancel new task"), else: "Close inspector")}
            >
              <Lucideicons.arrow_left class="icon app-inspector__back" />
              <Lucideicons.x class="icon app-inspector__x" />
            </button>
            <h2 class="app-inspector__title">
              {if @new_row, do: gettext("New task"), else: inspector_title(@inspector)}
            </h2>
          </div>
          <.live_component
            module={MarskalWeb.InspectorPanel}
            id="inspector"
            user={@current_scope.user}
            selection={@inspector}
            new_task={@new_row}
            change_version={@change_version}
          />
        </aside>
      </div>

      <nav :if={@nav} class="tab-bar" aria-label="Views">
        <.tab navigate={~p"/inbox"} current={@current_nav == :inbox}>
          <Lucideicons.inbox class="icon" /> Inbox
        </.tab>
        <.tab navigate={~p"/open"} current={@current_nav == :open}>
          <Lucideicons.list class="icon" /> Open
        </.tab>
        <.tab navigate={~p"/agenda"} current={@current_nav == :agenda}>
          <Lucideicons.calendar_days class="icon" /> Agenda
        </.tab>
        <.tab navigate={~p"/flagged"} current={@current_nav == :flagged}>
          <Lucideicons.flag class="icon" /> Flagged
        </.tab>
      </nav>

      <MarskalWeb.KeysHelp.dialog
        :if={@current_scope && @current_scope.user}
        keymap={keymap(@current_scope)}
      />

      <.live_component
        :if={@nav}
        module={MarskalWeb.GoTo}
        id="go-to"
        user={@current_scope.user}
        nav={@nav}
      />

      <.live_component
        :if={@nav && @current_nav != :inbox}
        module={MarskalWeb.QuickCapture}
        id="quick-capture"
        user={@current_scope.user}
      />
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Inspector" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      const outside = (el: Element, event: MouseEvent) => {
        const box = el.getBoundingClientRect()
        return event.clientX < box.left || event.clientX > box.right ||
          event.clientY < box.top || event.clientY > box.bottom
      }

      // Each navigation mounts a new LiveView and a new sidebar. Its scroll
      // position is read as the navigation starts and kept here, in the
      // bundle, so the next one starts there.
      let sidebarTop: number | null = null
      window.addEventListener("phx:page-loading-start", () => {
        const sidebar = document.getElementById("sidebar")
        if (sidebar) sidebarTop = sidebar.scrollTop
      })

      export default class extends ViewHook {
        wasOpen = false
        phone = window.matchMedia("(max-width: 720px)")
        narrow = window.matchMedia("(max-width: 64rem)")

        onClick = (event: MouseEvent) => {
          if (!(event.target instanceof Element)) return
          if (this.onCaptureClick(event)) return
          if (event.target.closest(".app-header__menu")) {
            this.setNav(!document.body.classList.contains("nav-open"))
            return
          }
          if (event.target.closest(".sidebar-backdrop, .sidebar a")) this.setNav(false)
          const link = event.target.closest("a")
          if (link) {
            if (link.hasAttribute("data-opens-inspector") && this.narrow.matches) this.skipInspector(link)
            if (link.closest(".task-row")) event.stopPropagation()
            return
          }
          if (event.target.closest("button, input, select, textarea, label, [phx-click]")) return
          const row = event.target.closest<HTMLElement>("[data-inspect-type][data-inspect-id]")
          if (!row || !this.el.contains(row)) return
          this.pushEvent("inspect", {type: row.dataset.inspectType, id: row.dataset.inspectId})
        }

        onKeydown = (event: KeyboardEvent) => {
          if (event.key !== "Escape") return
          if (document.querySelector("dialog[open]")) return
          if (event.target instanceof Element && event.target.closest(".add-form, .task-new")) return
          if (document.body.classList.contains("nav-open")) {
            event.preventDefault()
            this.setNav(false)
            return
          }
          if (!this.el.classList.contains("is-inspector-open")) return
          event.preventDefault()
          // A new task's fields are the inspector. Escape ends the draft,
          // the same as Escape in its title.
          if (document.getElementById("inspector-new-task")) {
            this.pushEvent("inline-cancel", {})
            return
          }
          // Closing from inside the inspector hands focus back to its row.
          const panel = this.el.querySelector(".app-inspector")
          if (panel?.contains(document.activeElement)) {
            this.el.querySelector<HTMLElement>(".task-row.is-selected button.select")?.focus()
          }
          this.pushEvent("close-inspector", {})
        }

        mounted() {
          this.el.addEventListener("click", this.onClick)
          const sidebar = this.el.querySelector<HTMLElement>(".sidebar")
          if (sidebar && sidebarTop !== null) sidebar.scrollTop = sidebarTop
          document.addEventListener("keydown", this.onKeydown)
          this.phone.addEventListener("change", this.onResize)
          this.handleEvent("quick-capture:added", ({id}: {id: string}) => {
            document.getElementById(id)?.closest("dialog")?.close()
          })
          this.setNav(false)
          this.sync()
        }

        updated() {
          this.sync()
        }

        destroyed() {
          this.el.removeEventListener("click", this.onClick)
          document.removeEventListener("keydown", this.onKeydown)
          this.phone.removeEventListener("change", this.onResize)
          document.body.classList.remove("inspector-open", "nav-open")
        }

        onResize = () => {
          this.setNav(false)
          this.sync()
        }

        // The add button opens its sheet; the close button or a tap on the
        // backdrop, which targets the dialog itself, closes it.
        onCaptureClick(event: MouseEvent): boolean {
          const target = event.target as Element
          const capture = target.closest(".quick-capture")
          if (!capture) return false
          const dialog = capture.querySelector("dialog")
          if (!dialog) return false
          if (target.closest(".open")) dialog.showModal()
          else if (target.closest(".close") || (target === dialog && outside(dialog, event))) dialog.close()
          else return false
          return true
        }

        // A record link opens the inspector with its page only when there is
        // room for three panes. LiveView reads the href after this handler.
        skipInspector(link: HTMLAnchorElement) {
          const url = new URL(link.href)
          for (const key of ["task", "project", "folder", "tag"]) url.searchParams.delete(key)
          link.setAttribute("href", url.pathname + url.search)
        }

        // On a phone the sidebar is a drawer behind the menu button. The
        // state lives on <body>, outside what LiveView patches.
        setNav(open: boolean) {
          const sidebar = this.el.querySelector<HTMLElement>(".sidebar")
          const button = this.el.querySelector<HTMLElement>(".app-header__menu")
          if (!sidebar || !button) return
          const opened = open && !document.body.classList.contains("nav-open")
          document.body.classList.toggle("nav-open", open)
          button.setAttribute("aria-expanded", String(open))
          sidebar.toggleAttribute("inert", this.phone.matches && !open)
          if (opened) sidebar.focus({preventScroll: true})
        }

        sync() {
          const panel = this.el.querySelector<HTMLElement>(".app-inspector")
          if (!panel) return
          const open = this.el.classList.contains("is-inspector-open")
          const narrow = this.narrow.matches
          panel.toggleAttribute("inert", narrow && !open)
          document.body.classList.toggle("inspector-open", narrow && open)
          // A sheet takes focus as it opens. Beside the list, focus stays
          // on the row, so the list keys go on from there (ADR 0031).
          // A new task's title is in the sheet on a narrow window, because
          // the row it belongs to is covered.
          if (open && !this.wasOpen && narrow) {
            const title = document.getElementById("inspector-new-task-title")
            if (title instanceof HTMLElement) title.focus({preventScroll: true})
            else panel.focus({preventScroll: true})
          }
          this.wasOpen = open
        }
      }
    </script>

    <.flash_group flash={@flash} />
    """
  end

  # The keyboard map for list navigation (ADR 0031), from the preferences
  # the session preloads. A signed-out page has none, and the standard map
  # is the default.
  defp keymap(%{user: user}) when not is_nil(user), do: Marskal.Accounts.preferences(user).keymap
  defp keymap(_scope), do: :standard

  defp inspector_title(%{type: :task}), do: "Task"
  defp inspector_title(%{type: :project}), do: "Project"
  defp inspector_title(%{type: :folder}), do: "Folder"
  defp inspector_title(%{type: :tag}), do: "Tag"
  defp inspector_title(_selection), do: "Details"

  attr :navigate, :string, required: true
  attr :current, :boolean, default: false
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <.link navigate={@navigate} class={@current && "is-current"} aria-current={@current && "page"}>
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :visibility, :list, required: true

  @doc """
  Done, Dropped, and Deferred, for this browser only: three toggles beside
  the theme's. The server filters by `MarskalWeb.Visibility`; this hook
  stores a toggle in the cookie and passes it to the browser's other tabs.
  """
  def visibility_toggle(assigns) do
    ~H"""
    <div
      id="visibility"
      class="visibility"
      role="group"
      aria-labelledby="visibility-label"
      data-visibility={MarskalWeb.Visibility.encode(@visibility)}
      phx-hook=".Visibility"
    >
      <span id="visibility-label" class="visibility__label">{gettext("Show")}</span>
      <button
        :for={
          {kind, label, hint} <- [
            {:done, gettext("Done"), gettext("Show done tasks and projects")},
            {:dropped, gettext("Dropped"),
             gettext("Show dropped tasks, projects, folders, and tags")},
            {:deferred, gettext("Deferred"), gettext("Show deferred tasks and projects")}
          ]
        }
        type="button"
        id={"visibility-#{kind}"}
        aria-pressed={to_string(kind in @visibility)}
        title={hint}
        phx-click="visibility"
        phx-value-kind={kind}
      >
        <Lucideicons.square_check_big :if={kind == :done} class="icon" />
        <Lucideicons.square_off :if={kind == :dropped} class="icon" />
        <Lucideicons.hourglass :if={kind == :deferred} class="icon" />
        <span class="visibility__name">{label}</span>
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Visibility" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // Must match MarskalWeb.Visibility and the connect params in app.ts.
      const cookie = "marskal_visibility"
      const year = 60 * 60 * 24 * 365

      export default class extends ViewHook {
        channel: BroadcastChannel | null = null

        mounted() {
          this.channel = new BroadcastChannel(cookie)
          this.channel.onmessage = (event: MessageEvent) => {
            if (typeof event.data === "string" && event.data !== this.el.dataset.visibility) {
              this.pushEvent("visibility", {value: event.data})
            }
          }

          this.handleEvent("visibility", ({value}: {value: string}) => {
            document.cookie = `${cookie}=${value}; path=/; max-age=${year}; samesite=lax`
            this.channel?.postMessage(value)
          })
        }

        destroyed() {
          this.channel?.close()
        }
      }
    </script>
    """
  end

  @doc """
  Light, dark, or the system's scheme, for this browser only. The root
  layout applies the saved choice before the page paints; this hook saves
  a new one and marks the pressed button.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      class="theme-toggle"
      role="group"
      aria-label={gettext("Theme")}
      phx-hook=".ThemeToggle"
    >
      <button
        :for={
          {theme, label} <- [
            {"light", gettext("Light")},
            {"dark", gettext("Dark")},
            {"auto", gettext("Automatic")}
          ]
        }
        type="button"
        data-theme-choice={theme}
        aria-pressed={to_string(theme == "auto")}
        aria-label={label}
        title={label}
        phx-mounted={JS.ignore_attributes("aria-pressed")}
      >
        <Lucideicons.sun :if={theme == "light"} class="icon" />
        <Lucideicons.moon :if={theme == "dark"} class="icon" />
        <Lucideicons.sun_moon :if={theme == "auto"} class="icon" />
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".ThemeToggle" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // Must match the script in root.html.heex. Automatic is no entry.
      const key = "marskal:theme"
      type Theme = "light" | "dark" | "auto"

      function stored(): Theme {
        try {
          const theme = localStorage.getItem(key)
          return theme === "light" || theme === "dark" ? theme : "auto"
        } catch {
          return "auto"
        }
      }

      function apply(theme: Theme) {
        if (theme === "auto") delete document.documentElement.dataset.theme
        else document.documentElement.dataset.theme = theme
      }

      export default class extends ViewHook {
        // Another tab's choice applies here too.
        onStorage = (event: StorageEvent) => {
          if (event.key !== key) return
          apply(stored())
          this.mark()
        }

        mounted() {
          this.mark()
          window.addEventListener("storage", this.onStorage)
          this.el.addEventListener("click", (event) => {
            if (!(event.target instanceof Element)) return
            const theme = event.target.closest<HTMLElement>("[data-theme-choice]")?.dataset.themeChoice
            if (theme !== "light" && theme !== "dark" && theme !== "auto") return
            try {
              if (theme === "auto") localStorage.removeItem(key)
              else localStorage.setItem(key, theme)
            } catch {
              // Private windows may refuse storage; the choice holds until reload.
            }
            apply(theme)
            this.mark()
          })
        }

        destroyed() {
          window.removeEventListener("storage", this.onStorage)
        }

        mark() {
          const current = document.documentElement.dataset.theme ?? "auto"
          for (const button of this.el.querySelectorAll<HTMLElement>("[data-theme-choice]")) {
            button.setAttribute("aria-pressed", String(button.dataset.themeChoice === current))
          }
        }
      }
    </script>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <Lucideicons.loader_circle class="icon icon-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <Lucideicons.loader_circle class="icon icon-spin" />
      </.flash>
    </div>
    """
  end
end
