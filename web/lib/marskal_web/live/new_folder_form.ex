defmodule MarskalWeb.NewFolderForm do
  @moduledoc """
  The form that creates a project folder.
  """

  use MarskalWeb, :live_component

  alias Marskal.ProjectFolders

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns) |> assign(:command_id, Ecto.UUID.generate(version: 7))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id={@id} phx-submit="create" phx-target={@myself} class="capture">
      <input type="hidden" name="command_id" value={@command_id} />
      <label for={"#{@id}-name"}>New folder</label>
      <input type="text" name="project_folder[name]" id={"#{@id}-name"} />
      <button type="submit">Add folder</button>
    </form>
    """
  end

  @impl true
  def handle_event(
        "create",
        %{"project_folder" => %{"name" => name}, "command_id" => command_id},
        socket
      ) do
    case ProjectFolders.create_folder(socket.assigns.user, %{"name" => name}, command_id) do
      {:ok, folder} ->
        {:noreply, push_navigate(socket, to: ~p"/folders/#{folder.id}")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add folder.")}
    end
  end
end
