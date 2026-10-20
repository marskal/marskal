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
      phx-mounted={JS.ignore_attributes("inert")}
    >
      <MarskalWeb.NavOutline.scope id="sidebar-nav">
        <nav class="sidebar-links">
          <.view_link navigate={~p"/inbox"} current={@current_nav == :inbox} class="in-tab-bar">
            <Lucideicons.inbox class="icon" /> Inbox
          </.view_link>
          <.view_link navigate={~p"/open"} current={@current_nav == :open} class="in-tab-bar">
            <Lucideicons.list class="icon" /> Open
          </.view_link>
          <.view_link navigate={~p"/agenda"} current={@current_nav == :agenda} class="in-tab-bar">
            <Lucideicons.calendar_days class="icon" /> Agenda
          </.view_link>
          <.view_link navigate={~p"/flagged"} current={@current_nav == :flagged} class="in-tab-bar">
            <Lucideicons.flag class="icon" /> Flagged
          </.view_link>
          <.view_link navigate={~p"/imports"} current={@current_nav == :import}>
            <Lucideicons.download class="icon" /> Import
          </.view_link>
        </nav>

        <.live_component module={MarskalWeb.NewFolderForm} id="new-root-folder" user={@user} />

        <p :if={Marskal.ProjectNav.empty?(@nav)} class="empty">No projects yet.</p>

        <MarskalWeb.NavOutline.list
          id="sidebar-projects"
          class="nav-tree"
          rows={MarskalWeb.NavOutline.project_rows(@nav, nil)}
          current_id={@current_id}
          inspector={@inspector}
          label={gettext("Folders and projects")}
        />

        <.live_component module={MarskalWeb.NewTagForm} id="new-root-tag" user={@user} />
        <MarskalWeb.NavOutline.list
          id="sidebar-tags"
          class="nav-tree"
          rows={
            MarskalWeb.NavOutline.tag_rows(
              @nav.tags,
              nil,
              &Marskal.ProjectNav.tag_shown?(@nav, &1.id)
            )
          }
          current_id={@current_id}
          inspector={@inspector}
          label={gettext("Tags")}
        />
        <ul class="nav-tree">
          <li class="nav-row">
            <.view_link navigate={~p"/tags/untagged"} current={@current_nav == :untagged}>
              <Lucideicons.tag class="icon" /> Untagged
            </.view_link>
          </li>
        </ul>
      </MarskalWeb.NavOutline.scope>

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
    """
  end

  attr :navigate, :string, required: true
  attr :current, :boolean, default: false
  attr :class, :string, default: nil
  slot :inner_block, required: true

  # A view at the top of the sidebar. The keys move through these and the
  # outlines below; only the outlines rearrange.
  defp view_link(assigns) do
    ~H"""
    <.link
      navigate={@navigate}
      class={[@class, @current && "is-current"]}
      aria-current={@current && "page"}
      data-nav-stop
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :type, :atom, required: true, values: [:project, :folder, :tag]
  attr :id, :string, required: true
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil

  attr :nav_stop, :boolean,
    default: false,
    doc: "a row the outline keys move to and the pointer drags"

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
      data-nav-stop={@nav_stop}
      draggable={@nav_stop && "false"}
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
end
