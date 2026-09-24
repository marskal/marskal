defmodule MarskalWeb.Inspector do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Marskal.ProjectFolders
  alias Marskal.ProjectNav
  alias Marskal.Projects
  alias Marskal.Tasks

  def selected?(type, id, %{type: type, id: id}), do: true
  def selected?(_type, _id, _selection), do: false

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> attach_hook(:inspector_params, :handle_params, &on_params/3)
     |> attach_hook(:inspector_event, :handle_event, &on_event/3)
     |> attach_hook(:inspector_info, :handle_info, &on_info/2)}
  end

  defp on_params(params, uri, socket) do
    socket =
      socket
      |> assign(:inspector, selection(params))
      |> assign(:inspector_path, URI.parse(uri).path)

    # push_patch always asks the view for handle_params/3. A view that does not
    # define one must be halted here, or the patch crashes. Views that do
    # define it, such as the import page, still run after this hook.
    if function_exported?(socket.view, :handle_params, 3) do
      {:cont, socket}
    else
      {:halt, socket}
    end
  end

  defp on_event("inspect", %{"type" => type, "id" => id}, socket)
       when type in ["task", "project", "folder"] and is_binary(id) do
    {:halt, push_patch(socket, to: query_path(socket, %{type => id}))}
  end

  defp on_event("close-inspector", _params, socket) do
    {:halt, push_patch(socket, to: socket.assigns.inspector_path)}
  end

  defp on_event(_event, _params, socket), do: {:cont, socket}

  defp on_info(:inspector_saved, socket) do
    {:halt, reload(socket)}
  end

  defp on_info(_message, socket), do: {:cont, socket}

  defp selection(params) do
    cond do
      id = present(params["task"]) -> %{type: :task, id: id}
      id = present(params["project"]) -> %{type: :project, id: id}
      id = present(params["folder"]) -> %{type: :folder, id: id}
      true -> nil
    end
  end

  defp present(id) when is_binary(id) and id != "", do: id
  defp present(_), do: nil

  defp query_path(socket, query) do
    socket.assigns.inspector_path <> "?" <> URI.encode_query(query)
  end

  defp reload(socket) do
    # The sidebar is built while the page renders, so a save has to change an
    # assign even when the list on this page did not.
    socket = assign(socket, :inspector_refresh, System.unique_integer([:positive]))
    user = socket.assigns.current_scope.user

    case socket.view do
      MarskalWeb.OpenTasksLive ->
        assign(socket, :tasks, Tasks.list_open(user))

      MarskalWeb.InboxLive ->
        assign(socket, :tasks, Tasks.list_inbox(user))

      MarskalWeb.ProjectLive ->
        project = Projects.get_project(user, socket.assigns.project.id) || socket.assigns.project

        folder =
          if project.project_folder_id,
            do: ProjectFolders.get_folder(user, project.project_folder_id)

        socket
        |> assign(:page_title, project.title)
        |> assign(:project, project)
        |> assign(:folder, folder)
        |> assign(:tasks, Tasks.list_project_tasks(user, project.id))

      MarskalWeb.FolderLive ->
        folder =
          ProjectFolders.get_folder(user, socket.assigns.folder.id) || socket.assigns.folder

        nav = ProjectNav.build(user)

        socket
        |> assign(:page_title, folder.name)
        |> assign(:folder, folder)
        |> assign(:children, ProjectNav.child_folders(nav, folder))
        |> assign(:projects, ProjectNav.projects_in(nav, folder))

      MarskalWeb.TaskLive ->
        case Tasks.get_task(user, socket.assigns.task.id) do
          nil ->
            socket

          task ->
            socket
            |> assign(:page_title, task.title)
            |> assign(:task, task)
            |> assign(:projects, Projects.list_open(user))
            |> assign(
              :form,
              Phoenix.Component.to_form(
                %{
                  "title" => task.title,
                  "notes" => task.notes,
                  "project_id" => task.project_id
                },
                as: "task"
              )
            )
        end

      _view ->
        socket
    end
  end
end
