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
  attr :nav, :any, default: nil, doc: "the sidebar tree, assigned by MarskalWeb.Inspector"
  attr :change_version, :integer, default: 0

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div
      id="app-shell"
      class={["app", @inspector && "is-inspector-open"]}
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
          <.link navigate={~p"/"}>
            <img src={~p"/images/icon.svg"} alt="" class="app-header__logo" />
            <span>Marskal</span>
          </.link>
        </div>
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
        <main class="app-main">
          {render_slot(@inner_block)}
        </main>
        <div
          :if={@current_scope && @current_scope.user}
          class="app-inspector__backdrop"
          phx-click="close-inspector"
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
              phx-click="close-inspector"
              aria-label="Close inspector"
            >
              <Lucideicons.arrow_left class="icon app-inspector__back" />
              <Lucideicons.x class="icon app-inspector__x" />
            </button>
            <h2 class="app-inspector__title">{inspector_title(@inspector)}</h2>
          </div>
          <.live_component
            module={MarskalWeb.InspectorPanel}
            id="inspector"
            user={@current_scope.user}
            selection={@inspector}
            change_version={@change_version}
          />
        </aside>
      </div>

      <nav :if={@nav} class="tab-bar" aria-label="Views">
        <.tab navigate={~p"/inbox"} current={@current_nav == :inbox}>
          <Lucideicons.inbox class="icon" /> Inbox
        </.tab>
        <.tab navigate={~p"/"} current={@current_nav == :open}>
          <Lucideicons.list class="icon" /> Open
        </.tab>
        <.tab navigate={~p"/agenda"} current={@current_nav == :agenda}>
          <Lucideicons.calendar_days class="icon" /> Agenda
        </.tab>
        <.tab navigate={~p"/flagged"} current={@current_nav == :flagged}>
          <Lucideicons.flag class="icon" /> Flagged
        </.tab>
      </nav>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Inspector" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      export default class extends ViewHook {
        wasOpen = false
        phone = window.matchMedia("(max-width: 720px)")
        narrow = window.matchMedia("(max-width: 64rem)")

        onClick = (event: MouseEvent) => {
          if (!(event.target instanceof Element)) return
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
          if (document.body.classList.contains("nav-open")) {
            event.preventDefault()
            this.setNav(false)
            return
          }
          if (!this.el.classList.contains("is-inspector-open")) return
          event.preventDefault()
          this.pushEvent("close-inspector", {})
        }

        mounted() {
          this.el.addEventListener("click", this.onClick)
          document.addEventListener("keydown", this.onKeydown)
          this.phone.addEventListener("change", this.onResize)
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
          if (open && !this.wasOpen) panel.focus({preventScroll: true})
          this.wasOpen = open
        }
      }
    </script>

    <.flash_group flash={@flash} />
    """
  end

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
