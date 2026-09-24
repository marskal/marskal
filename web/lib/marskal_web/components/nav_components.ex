defmodule MarskalWeb.NavComponents do
  use MarskalWeb, :html

  attr :nav, :any, required: true
  attr :user, :any, required: true
  attr :current_nav, :atom, default: nil
  attr :current_id, :string, default: nil

  def sidebar(assigns) do
    ~H"""
    <aside class="sidebar">
      <nav class="sidebar-links">
        <.link navigate={~p"/inbox"} class={link_class(@current_nav, :inbox)}>Inbox</.link>
        <.link navigate={~p"/"} class={link_class(@current_nav, :open)}>Open</.link>
      </nav>

      <p :if={Marskal.ProjectNav.empty?(@nav)} class="empty">No projects yet.</p>

      <ul class="nav-tree">
        <MarskalWeb.NavComponents.folder
          :for={folder <- Marskal.ProjectNav.root_folders(@nav)}
          nav={@nav}
          folder={folder}
          current_id={@current_id}
        />
      </ul>

      <ul :if={Marskal.ProjectNav.unfiled_projects(@nav) != []} class="nav-tree">
        <li :for={project <- Marskal.ProjectNav.unfiled_projects(@nav)}>
          <.link
            navigate={~p"/projects/#{project.id}"}
            class={id_class(@current_id, project.id)}
          >
            {project.title}
          </.link>
        </li>
      </ul>

      <.live_component module={MarskalWeb.NewFolderForm} id="new-root-folder" user={@user} />
    </aside>
    """
  end

  attr :nav, :any, required: true
  attr :folder, :any, required: true
  attr :current_id, :string, default: nil

  def folder(assigns) do
    ~H"""
    <li>
      <.link navigate={~p"/folders/#{@folder.id}"} class={id_class(@current_id, @folder.id)}>
        {@folder.name}
      </.link>
      <ul>
        <MarskalWeb.NavComponents.folder
          :for={child <- Marskal.ProjectNav.child_folders(@nav, @folder)}
          nav={@nav}
          folder={child}
          current_id={@current_id}
        />
        <li :for={project <- Marskal.ProjectNav.projects_in(@nav, @folder)}>
          <.link
            navigate={~p"/projects/#{project.id}"}
            class={id_class(@current_id, project.id)}
          >
            {project.title}
          </.link>
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
