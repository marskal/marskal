defmodule MarskalWeb.NewTagForm do
  use MarskalWeb, :live_component

  alias Marskal.Tags

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns) |> assign(:command_id, Ecto.UUID.generate())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <form id={@id} phx-submit="create" phx-target={@myself} class="capture">
      <input type="hidden" name="command_id" value={@command_id} />
      <label for={"#{@id}-name"}>New tag</label>
      <input type="text" name="tag[name]" id={"#{@id}-name"} autocomplete="off" />
      <button type="submit">Add tag</button>
    </form>
    """
  end

  @impl true
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

  defp name_error(changeset) do
    case changeset.errors do
      [{field, error} | _] -> "#{field} #{translate_error(error)}"
      [] -> "invalid"
    end
  end
end
