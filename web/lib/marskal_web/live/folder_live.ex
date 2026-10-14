defmodule MarskalWeb.FolderLive do
  use MarskalWeb, :live_view

  import MarskalWeb.NavComponents, only: [record_link: 1]

  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.Projects

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case ProjectFolders.get_folder(user, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That folder is not available.")
         |> MarskalWeb.UserAuth.redirect_home()}

      folder ->
        {:ok, assign_folder(socket, user, folder)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current_id={@folder.id}
      inspector={assigns[:inspector]}
      nav={assigns[:nav]}
      change_version={assigns[:change_version] || 0}
    >
      <p :if={@folder.parent_path != []} class="lede">{Enum.join(@folder.parent_path, " / ")}</p>
      <MarskalWeb.NavComponents.page_heading type={:folder} id={@folder.id} inspector={@inspector}>
        {@folder.name}
      </MarskalWeb.NavComponents.page_heading>
      <p class="actions">
        <button :if={@folder.state == :active} type="button" phx-click="drop">Drop</button>
        <button :if={@folder.state == :dropped} type="button" phx-click="activate">Activate</button>
      </p>

      <h2>Folders</h2>
      <ul class="nav-tree">
        <li :for={child <- @children}>
          <.record_link type={:folder} id={child.id} inspector={@inspector}>
            <Lucideicons.folder class="icon" /> {child.name}
          </.record_link>
        </li>
      </ul>
      <p :if={@children == []} class="empty">No folders inside.</p>

      <.add_form
        id="new-folder"
        for={@folder_form}
        field={@folder_form[:name]}
        label="New folder"
        command_id={@folder_command_id}
        phx-submit="create-folder"
      />

      <h2>Projects</h2>
      <ul class="nav-tree">
        <li :for={project <- @projects}>
          <.record_link type={:project} id={project.id} inspector={@inspector}>
            <Lucideicons.circle class="icon" /> {project.title}
          </.record_link>
        </li>
      </ul>
      <p :if={@projects == []} class="empty">No open projects.</p>

      <.add_form
        id="new-project"
        for={@project_form}
        field={@project_form[:title]}
        label="New project"
        command_id={@project_command_id}
        phx-submit="create-project"
      />
    </Layouts.app>
    """
  end

  @impl true
  def handle_info({:marskal_change, _type, _id}, socket) do
    user = socket.assigns.current_scope.user
    folder = ProjectFolders.get_folder(user, socket.assigns.folder.id) || socket.assigns.folder

    {:noreply, assign_records(socket, user, folder)}
  end

  @impl true
  def handle_event(
        "create-folder",
        %{"project_folder" => params, "command_id" => command_id},
        socket
      ) do
    user = socket.assigns.current_scope.user
    attrs = Map.put(params, "parent_id", socket.assigns.folder.id)

    case ProjectFolders.create_folder(user, attrs, command_id) do
      {:ok, _} -> {:noreply, assign_folder(socket, user, socket.assigns.folder)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not add folder.")}
    end
  end

  def handle_event("create-project", %{"project" => params, "command_id" => command_id}, socket) do
    user = socket.assigns.current_scope.user
    attrs = Map.put(params, "project_folder_id", socket.assigns.folder.id)

    case Projects.create_project(user, attrs, command_id) do
      {:ok, _} -> {:noreply, assign_folder(socket, user, socket.assigns.folder)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not add project.")}
    end
  end

  def handle_event("drop", _params, socket), do: state(socket, &ProjectFolders.drop_folder/3)

  def handle_event("activate", _params, socket),
    do: state(socket, &ProjectFolders.activate_folder/3)

  defp state(socket, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, socket.assigns.folder.id, Ecto.UUID.generate(version: 7)) do
      {:ok, folder} -> {:noreply, assign_folder(socket, user, folder)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update folder.")}
    end
  end

  defp assign_folder(socket, user, folder) do
    socket
    |> assign_records(user, folder)
    |> assign(:folder_command_id, Ecto.UUID.generate(version: 7))
    |> assign(:project_command_id, Ecto.UUID.generate(version: 7))
    |> assign(:folder_form, to_form(%{"name" => ""}, as: "project_folder"))
    |> assign(:project_form, to_form(%{"title" => ""}, as: "project"))
  end

  # Leaves the capture forms alone, so a broadcast does not clear typing.
  defp assign_records(socket, user, folder) do
    nav = ProjectNav.build(user)

    socket
    |> assign(:page_title, folder.name)
    |> assign(:folder, folder)
    |> assign(:children, ProjectNav.child_folders(nav, folder))
    |> assign(:projects, ProjectNav.projects_in(nav, folder))
  end
end
