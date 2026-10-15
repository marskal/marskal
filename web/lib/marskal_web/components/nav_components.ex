defmodule MarskalWeb.NavComponents do
  @moduledoc """
  The sidebar and the rest of the app navigation.
  """

  use MarskalWeb, :html

  attr :nav, :any, required: true
  attr :user, :any, required: true
  attr :current_nav, :atom, default: nil
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil

  def sidebar(assigns) do
    ~H"""
    <aside
      id="sidebar"
      class="sidebar"
      tabindex="-1"
      aria-label="Projects and tags"
      phx-hook=".NavTree"
      phx-mounted={JS.ignore_attributes("inert")}
    >
      <nav class="sidebar-links">
        <.link navigate={~p"/inbox"} class={["in-tab-bar", link_class(@current_nav, :inbox)]}>
          <Lucideicons.inbox class="icon" /> Inbox
        </.link>
        <.link navigate={~p"/open"} class={["in-tab-bar", link_class(@current_nav, :open)]}>
          <Lucideicons.list class="icon" /> Open
        </.link>
        <.link navigate={~p"/agenda"} class={["in-tab-bar", link_class(@current_nav, :agenda)]}>
          <Lucideicons.calendar_days class="icon" /> Agenda
        </.link>
        <.link navigate={~p"/flagged"} class={["in-tab-bar", link_class(@current_nav, :flagged)]}>
          <Lucideicons.flag class="icon" /> Flagged
        </.link>
        <.link navigate={~p"/imports"} class={link_class(@current_nav, :import)}>
          <Lucideicons.download class="icon" /> Import
        </.link>
      </nav>

      <.live_component module={MarskalWeb.NewFolderForm} id="new-root-folder" user={@user} />

      <p :if={Marskal.ProjectNav.empty?(@nav)} class="empty">No projects yet.</p>

      <ul class="nav-tree">
        <MarskalWeb.NavComponents.folder
          :for={folder <- Marskal.ProjectNav.root_folders(@nav)}
          nav={@nav}
          folder={folder}
          current_id={@current_id}
          inspector={@inspector}
        />
      </ul>

      <ul :if={Marskal.ProjectNav.unfiled_projects(@nav) != []} class="nav-tree">
        <li :for={project <- Marskal.ProjectNav.unfiled_projects(@nav)}>
          <.record_link
            type={:project}
            id={project.id}
            current_id={@current_id}
            inspector={@inspector}
          >
            <Lucideicons.circle class="icon" /> {project.title}
          </.record_link>
        </li>
      </ul>

      <.live_component module={MarskalWeb.NewTagForm} id="new-root-tag" user={@user} />
      <ul class="nav-tree" id="sidebar-tags">
        <MarskalWeb.NavComponents.tag
          :for={tag <- Marskal.ProjectNav.tags_in(@nav, nil)}
          nav={@nav}
          tag={tag}
          current_id={@current_id}
          inspector={@inspector}
        />
        <li>
          <.link navigate={~p"/tags/untagged"} class={link_class(@current_nav, :untagged)}>
            <Lucideicons.tag class="icon" /> Untagged
          </.link>
        </li>
      </ul>

      <div class="sidebar-account">
        <p class="who">{@user.email}</p>
        <.link :if={@user.superuser} href={~p"/dev/dashboard"}>
          <Lucideicons.gauge class="icon" /> Dashboard
        </.link>
        <.link href={~p"/users/settings"}>
          <Lucideicons.settings class="icon" /> Settings
        </.link>
        <.link href={~p"/users/log-out"} method="delete">
          <Lucideicons.log_out class="icon" /> Log out
        </.link>
      </div>
    </aside>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".NavTree" extension="ts">
      import {ViewHook} from "phoenix_live_view"

      // Collapsed folders and tags are kept per browser and never reach the
      // server. A toggle names the list it hides (aria-controls); the saved
      // set holds those list ids.
      const key = "marskal:sidebar:collapsed"

      function load(): Set<string> {
        try {
          const ids: unknown = JSON.parse(localStorage.getItem(key) ?? "[]")
          return new Set(Array.isArray(ids) ? ids.filter((id) => typeof id === "string") : [])
        } catch {
          return new Set()
        }
      }

      function save(ids: Set<string>) {
        try {
          localStorage.setItem(key, JSON.stringify([...ids]))
        } catch {
          // Private windows may refuse storage; the toggles still work.
        }
      }

      export default class extends ViewHook {
        collapsed = new Set<string>()

        mounted() {
          this.collapsed = load()
          this.apply()
          this.el.addEventListener("click", (event) => {
            if (!(event.target instanceof Element)) return
            const list = event.target.closest(".nav-toggle")?.getAttribute("aria-controls")
            if (!list) return
            if (!this.collapsed.delete(list)) this.collapsed.add(list)
            save(this.collapsed)
            this.apply()
          })
        }

        updated() {
          this.apply()
        }

        // Through this.js(), so the state outlives the server's patches.
        apply() {
          for (const toggle of this.el.querySelectorAll<HTMLElement>(".nav-toggle")) {
            const expanded = String(!this.collapsed.has(toggle.getAttribute("aria-controls") ?? ""))
            if (toggle.getAttribute("aria-expanded") !== expanded) {
              this.js().setAttribute(toggle, "aria-expanded", expanded)
            }
          }
        }
      }
    </script>
    """
  end

  attr :nav, :any, required: true
  attr :folder, :any, required: true
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil

  def folder(assigns) do
    folders = Marskal.ProjectNav.child_folders(assigns.nav, assigns.folder)
    projects = Marskal.ProjectNav.projects_in(assigns.nav, assigns.folder)

    assigns =
      assign(assigns,
        folders: folders,
        projects: projects,
        children?: folders != [] or projects != []
      )

    ~H"""
    <li>
      <.nav_toggle :if={@children?} list={"sidebar-folder-#{@folder.id}"} name={@folder.name} />
      <.record_link type={:folder} id={@folder.id} current_id={@current_id} inspector={@inspector}>
        <Lucideicons.folder class="icon" /> {@folder.name}
      </.record_link>
      <ul :if={@children?} id={"sidebar-folder-#{@folder.id}"}>
        <MarskalWeb.NavComponents.folder
          :for={child <- @folders}
          nav={@nav}
          folder={child}
          current_id={@current_id}
          inspector={@inspector}
        />
        <li :for={project <- @projects}>
          <.record_link
            type={:project}
            id={project.id}
            current_id={@current_id}
            inspector={@inspector}
          >
            <Lucideicons.circle class="icon" /> {project.title}
          </.record_link>
        </li>
      </ul>
    </li>
    """
  end

  attr :nav, :any, required: true
  attr :tag, :any, required: true
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil

  def tag(assigns) do
    assigns = assign(assigns, :children, Marskal.ProjectNav.tags_in(assigns.nav, assigns.tag.id))

    ~H"""
    <li>
      <.nav_toggle :if={@children != []} list={"sidebar-tag-#{@tag.id}"} name={@tag.name} />
      <.record_link type={:tag} id={@tag.id} current_id={@current_id} inspector={@inspector}>
        <Lucideicons.tag class="icon" /> {@tag.name}
      </.record_link>
      <ul :if={@children != []} id={"sidebar-tag-#{@tag.id}"}>
        <MarskalWeb.NavComponents.tag
          :for={child <- @children}
          nav={@nav}
          tag={child}
          current_id={@current_id}
          inspector={@inspector}
        />
      </ul>
    </li>
    """
  end

  attr :list, :string, required: true, doc: "the id of the list it shows and hides"
  attr :name, :string, required: true

  # Starts expanded; the sidebar's hook collapses what this browser saved.
  defp nav_toggle(assigns) do
    ~H"""
    <button
      type="button"
      class="nav-toggle"
      aria-controls={@list}
      aria-expanded="true"
      aria-label={gettext("Contents of %{name}", name: @name)}
    >
      <Lucideicons.chevron_right class="icon" />
    </button>
    """
  end

  attr :type, :atom, required: true, values: [:project, :folder, :tag]
  attr :id, :string, required: true
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil
  slot :inner_block, required: true

  @doc """
  A project, folder, or tag row. Opens the record's page with the inspector on it.
  On that page already, a patch only moves the inspector.
  """
  def record_link(assigns) do
    path = record_path(assigns.type, assigns.id)

    assigns =
      assign(
        assigns,
        :to,
        if(assigns.current_id == assigns.id, do: [patch: path], else: [navigate: path])
      )

    ~H"""
    <.link
      {@to}
      data-opens-inspector
      class={[
        "inspect-row",
        @current_id == @id && "is-current",
        MarskalWeb.Inspector.selected?(@type, @id, @inspector) && "is-selected"
      ]}
      aria-current={@current_id == @id && "page"}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :type, :atom, required: true, values: [:project, :folder, :tag]
  attr :id, :string, required: true
  attr :inspector, :any, default: nil
  slot :inner_block, required: true
  slot :extra, doc: "sits beside the title and wraps under it when the line is full"

  @doc """
  A record page's heading, with a button that opens the record in the
  inspector. Narrow screens need it: there the record's page opens alone.
  """
  def page_heading(assigns) do
    ~H"""
    <div class="page-heading">
      <div class="page-heading__main">
        <h1>{render_slot(@inner_block)}</h1>
        {render_slot(@extra)}
      </div>
      <button
        :if={!MarskalWeb.Inspector.selected?(@type, @id, @inspector)}
        type="button"
        class="page-heading__details"
        phx-click="inspect"
        phx-value-type={@type}
        phx-value-id={@id}
      >
        <Lucideicons.info class="icon" /> Details
      </button>
    </div>
    """
  end

  @doc "The record's page, with the inspector open on it."
  def record_path(:project, id), do: ~p"/projects/#{id}?#{[project: id]}"
  def record_path(:folder, id), do: ~p"/folders/#{id}?#{[folder: id]}"
  def record_path(:tag, id), do: ~p"/tags/#{id}?#{[tag: id]}"

  defp link_class(current, name) when current == name, do: "is-current"
  defp link_class(_current, _name), do: nil
end
