defmodule MarskalWeb.NewFolderForm do
  @moduledoc """
  The sidebar's Projects heading, with a button that opens a field for a new
  folder.
  """

  use MarskalWeb, :live_component

  alias Marskal.ProjectFolders

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)
    {:ok, if(Map.has_key?(socket.assigns, :open), do: socket, else: reset(socket, false))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"#{@id}-section"} class="sidebar-section">
      <div class="sidebar-section__head">
        <h2 class="sidebar-heading">Projects</h2>
        <button
          type="button"
          class="sidebar-add"
          phx-click="toggle"
          phx-target={@myself}
          aria-expanded={to_string(@open)}
          aria-label="New folder"
          title="New folder"
        >
          <Lucideicons.folder_plus class="icon" />
        </button>
      </div>
      <.add_form
        :if={@open}
        id={@id}
        for={@form}
        field={@form[:name]}
        input_id={"#{@id}-name"}
        label="New folder"
        command_id={@command_id}
        autofocus
        phx-submit="create"
        phx-target={@myself}
        phx-keydown="toggle"
        phx-key="Escape"
      />
    </div>
    """
  end

  @impl true
  def handle_event("toggle", _params, socket), do: {:noreply, reset(socket, !socket.assigns.open)}

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

  defp reset(socket, open) do
    socket
    |> assign(:open, open)
    |> assign(:command_id, Ecto.UUID.generate(version: 7))
    |> assign(:form, to_form(%{"name" => ""}, as: "project_folder"))
  end
end
