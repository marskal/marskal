defmodule MarskalWeb.NewTagForm do
  @moduledoc """
  The sidebar's Tags heading, with a button that opens a field for a new tag.
  """

  use MarskalWeb, :live_component

  alias Marskal.Tags

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
        <h2 class="sidebar-heading">Tags</h2>
        <button
          type="button"
          class="sidebar-add"
          phx-click="toggle"
          phx-target={@myself}
          aria-expanded={to_string(@open)}
          aria-label="New tag"
          title="New tag"
        >
          <Lucideicons.plus class="icon" />
        </button>
      </div>
      <.add_form
        :if={@open}
        id={@id}
        for={@form}
        field={@form[:name]}
        input_id={"#{@id}-name"}
        label="New tag"
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

  def handle_event("create", %{"tag" => %{"name" => name}, "command_id" => command_id}, socket) do
    case Tags.create_tag(socket.assigns.user, %{"name" => name}, command_id) do
      {:ok, tag} ->
        {:noreply, push_navigate(socket, to: ~p"/tags/#{tag.id}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, "Could not add tag: #{name_error(changeset)}.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add tag.")}
    end
  end

  defp reset(socket, open) do
    socket
    |> assign(:open, open)
    |> assign(:command_id, Ecto.UUID.generate(version: 7))
    |> assign(:form, to_form(%{"name" => ""}, as: "tag"))
  end

  defp name_error(changeset) do
    case changeset.errors do
      [{field, error} | _] -> "#{field} #{translate_error(error)}"
      [] -> "invalid"
    end
  end
end
