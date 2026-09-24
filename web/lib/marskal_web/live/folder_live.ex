defmodule MarskalWeb.FolderLive do
  use MarskalWeb, :live_view

  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.Projects

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    user = socket.assigns.current_scope.user

    case ProjectFolders.get_folder(user, id) do
      nil ->
        {:ok, socket |> put_flash(:error, "That folder is not available.") |> redirect(to: ~p"/")}

      folder ->
        {:ok, assign_folder(socket, user, folder)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_id={@folder.id}>
      <p :if={@folder.parent_path != []} class="lede">{Enum.join(@folder.parent_path, " / ")}</p>
      <h1>{@folder.name}</h1>
      <p class="actions">
        <button :if={@folder.state == :active} type="button" phx-click="drop">Drop</button>
        <button :if={@folder.state == :dropped} type="button" phx-click="activate">Activate</button>
      </p>

      <h2>Folders</h2>
      <ul class="nav-tree">
        <li :for={child <- @children}>
          <.link navigate={~p"/folders/#{child.id}"}>{child.name}</.link>
        </li>
      </ul>
      <p :if={@children == []} class="empty">No folders inside.</p>

      <.form for={@folder_form} id="new-folder" phx-submit="create-folder" class="capture">
        <input type="hidden" name="command_id" value={@folder_command_id} />
        <label for={@folder_form[:name].id}>New folder</label>
        <input type="text" name={@folder_form[:name].name} id={@folder_form[:name].id} required />
        <button type="submit">Add folder</button>
      </.form>

      <h2>Projects</h2>
      <ul class="nav-tree">
        <li :for={project <- @projects}>
          <.link navigate={~p"/projects/#{project.id}"}>{project.title}</.link>
        </li>
      </ul>
      <p :if={@projects == []} class="empty">No open projects.</p>

      <.form for={@project_form} id="new-project" phx-submit="create-project" class="capture">
        <input type="hidden" name="command_id" value={@project_command_id} />
        <label for={@project_form[:title].id}>New project</label>
        <input type="text" name={@project_form[:title].name} id={@project_form[:title].id} required />
        <button type="submit">Add project</button>
      </.form>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create-folder", %{"project_folder" => params, "command_id" => command_id}, socket) do
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
  def handle_event("activate", _params, socket), do: state(socket, &ProjectFolders.activate_folder/3)

  defp state(socket, fun) do
    user = socket.assigns.current_scope.user

    case fun.(user, socket.assigns.folder.id, Ecto.UUID.generate()) do
      {:ok, folder} -> {:noreply, assign_folder(socket, user, folder)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not update folder.")}
    end
  end

  defp assign_folder(socket, user, folder) do
    nav = ProjectNav.build(user)

    socket
    |> assign(:page_title, folder.name)
    |> assign(:folder, folder)
    |> assign(:children, ProjectNav.child_folders(nav, folder))
    |> assign(:projects, ProjectNav.projects_in(nav, folder))
    |> assign(:folder_command_id, Ecto.UUID.generate())
    |> assign(:project_command_id, Ecto.UUID.generate())
    |> assign(:folder_form, to_form(%{"name" => ""}, as: "project_folder"))
    |> assign(:project_form, to_form(%{"title" => ""}, as: "project"))
  end
end
