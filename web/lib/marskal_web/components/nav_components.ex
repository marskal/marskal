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
    <aside id="sidebar" class="sidebar">
      <nav class="sidebar-links">
        <.link navigate={~p"/inbox"} class={link_class(@current_nav, :inbox)}>
          <Lucideicons.inbox class="icon" /> Inbox
        </.link>
        <.link navigate={~p"/"} class={link_class(@current_nav, :open)}>
          <Lucideicons.list class="icon" /> Open
        </.link>
        <.link navigate={~p"/agenda"} class={link_class(@current_nav, :agenda)}>
          <Lucideicons.calendar_days class="icon" /> Agenda
        </.link>
        <.link navigate={~p"/imports"} class={link_class(@current_nav, :import)}>
          <Lucideicons.download class="icon" /> Import
        </.link>
      </nav>

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

      <.live_component module={MarskalWeb.NewFolderForm} id="new-root-folder" user={@user} />

      <h2 class="sidebar-heading">Tags</h2>
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
      <.live_component module={MarskalWeb.NewTagForm} id="new-root-tag" user={@user} />
    </aside>
    """
  end

  attr :nav, :any, required: true
  attr :folder, :any, required: true
  attr :current_id, :string, default: nil
  attr :inspector, :any, default: nil

  def folder(assigns) do
    ~H"""
    <li>
      <.record_link type={:folder} id={@folder.id} current_id={@current_id} inspector={@inspector}>
        <Lucideicons.folder class="icon" /> {@folder.name}
      </.record_link>
      <ul>
        <MarskalWeb.NavComponents.folder
          :for={child <- Marskal.ProjectNav.child_folders(@nav, @folder)}
          nav={@nav}
          folder={child}
          current_id={@current_id}
          inspector={@inspector}
        />
        <li :for={project <- Marskal.ProjectNav.projects_in(@nav, @folder)}>
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
    ~H"""
    <li>
      <.record_link type={:tag} id={@tag.id} current_id={@current_id} inspector={@inspector}>
        <Lucideicons.tag class="icon" /> {@tag.name}
      </.record_link>
      <ul :if={Marskal.ProjectNav.tags_in(@nav, @tag.id) != []}>
        <MarskalWeb.NavComponents.tag
          :for={child <- Marskal.ProjectNav.tags_in(@nav, @tag.id)}
          nav={@nav}
          tag={child}
          current_id={@current_id}
          inspector={@inspector}
        />
      </ul>
    </li>
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

  @doc "The record's page, with the inspector open on it."
  def record_path(:project, id), do: ~p"/projects/#{id}?#{[project: id]}"
  def record_path(:folder, id), do: ~p"/folders/#{id}?#{[folder: id]}"
  def record_path(:tag, id), do: ~p"/tags/#{id}?#{[tag: id]}"

  defp link_class(current, name) when current == name, do: "is-current"
  defp link_class(_current, _name), do: nil
end
