defmodule MarskalWeb.NavComponents do
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
        <li
          :for={project <- Marskal.ProjectNav.unfiled_projects(@nav)}
          class={[
            "inspect-row",
            MarskalWeb.Inspector.selected?(:project, project.id, @inspector) && "is-selected"
          ]}
          data-inspect-type="project"
          data-inspect-id={project.id}
          aria-current={MarskalWeb.Inspector.selected?(:project, project.id, @inspector) && "true"}
        >
          <button
            type="button"
            class="select"
            phx-click="inspect"
            phx-value-type="project"
            phx-value-id={project.id}
          >
            <Lucideicons.circle class="icon" /> {project.title}
          </button>
          <.link navigate={~p"/projects/#{project.id}"} class="open-quiet">Open</.link>
        </li>
      </ul>

      <.live_component module={MarskalWeb.NewFolderForm} id="new-root-folder" user={@user} />
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
      <div
        class={[
          "inspect-row",
          MarskalWeb.Inspector.selected?(:folder, @folder.id, @inspector) && "is-selected"
        ]}
        data-inspect-type="folder"
        data-inspect-id={@folder.id}
        aria-current={MarskalWeb.Inspector.selected?(:folder, @folder.id, @inspector) && "true"}
      >
        <button
          type="button"
          class={["select", id_class(@current_id, @folder.id)]}
          phx-click="inspect"
          phx-value-type="folder"
          phx-value-id={@folder.id}
        >
          <Lucideicons.folder class="icon" /> {@folder.name}
        </button>
        <.link navigate={~p"/folders/#{@folder.id}"} class="open-quiet">Open</.link>
      </div>
      <ul>
        <MarskalWeb.NavComponents.folder
          :for={child <- Marskal.ProjectNav.child_folders(@nav, @folder)}
          nav={@nav}
          folder={child}
          current_id={@current_id}
          inspector={@inspector}
        />
        <li
          :for={project <- Marskal.ProjectNav.projects_in(@nav, @folder)}
          class={[
            "inspect-row",
            MarskalWeb.Inspector.selected?(:project, project.id, @inspector) && "is-selected"
          ]}
          data-inspect-type="project"
          data-inspect-id={project.id}
          aria-current={MarskalWeb.Inspector.selected?(:project, project.id, @inspector) && "true"}
        >
          <button
            type="button"
            class="select"
            phx-click="inspect"
            phx-value-type="project"
            phx-value-id={project.id}
          >
            <Lucideicons.circle class="icon" /> {project.title}
          </button>
          <.link navigate={~p"/projects/#{project.id}"} class="open-quiet">Open</.link>
        </li>
      </ul>
    </li>
    """
  end

  defp link_class(current, name) when current == name, do: "is-current"
  defp link_class(_current, _name), do: nil

  defp id_class(current, id) when current == id, do: "is-current"
  defp id_class(_current, _id), do: nil
end
