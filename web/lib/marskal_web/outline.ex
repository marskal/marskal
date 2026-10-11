defmodule MarskalWeb.Outline do
  @moduledoc """
  The outline events of a task list shown with `outline: true`: collapse,
  and the keyboard moves from the `.Outline` hook (ADR 0009).

  `attach/1` adds them to a LiveView. A move goes through `Marskal.Tasks`,
  and the change broadcast reloads the list, as any other write does.
  Collapsed ids belong to the browser: the hook sends its saved set on
  mount and saves what the server sends back after each toggle.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, put_flash: 3]

  alias Marskal.Tasks

  @moves %{
    "outline-indent" => &Tasks.indent_task/3,
    "outline-outdent" => &Tasks.outdent_task/3,
    "outline-up" => &Tasks.move_task_up/3,
    "outline-down" => &Tasks.move_task_down/3
  }

  @move_events Map.keys(@moves)

  def attach(socket) do
    socket
    |> assign(:collapsed, MapSet.new())
    |> attach_hook(:outline, :handle_event, &handle_event/3)
  end

  defp handle_event("outline-collapsed", %{"ids" => ids}, socket) when is_list(ids),
    do: {:halt, assign(socket, :collapsed, MapSet.new(ids, &to_string/1))}

  defp handle_event("outline-toggle", %{"id" => id}, socket) do
    collapsed = socket.assigns.collapsed

    collapsed =
      if MapSet.member?(collapsed, id),
        do: MapSet.delete(collapsed, id),
        else: MapSet.put(collapsed, id)

    {:halt,
     socket
     |> assign(:collapsed, collapsed)
     |> push_event("outline-collapsed", %{ids: MapSet.to_list(collapsed)})}
  end

  defp handle_event(event, %{"id" => id}, socket) when event in @move_events do
    user = socket.assigns.current_scope.user

    case @moves[event].(user, id, Ecto.UUID.generate(version: 7)) do
      {:ok, _task} ->
        {:halt, socket}

      # Nothing to indent under, out of, or past: the key does nothing.
      {:error, reason} when reason in [:first, :last, :top_level] ->
        {:halt, socket}

      {:error, _} ->
        {:halt, put_flash(socket, :error, "Could not move that task.")}
    end
  end

  # A drop: under `parent_id`, after `after_id` (either may be nil).
  defp handle_event("outline-place", %{"id" => id} = params, socket) do
    user = socket.assigns.current_scope.user

    case Tasks.place_task(
           user,
           id,
           params["parent_id"],
           params["after_id"],
           Ecto.UUID.generate(version: 7)
         ) do
      {:ok, _task} -> {:halt, socket}
      {:error, _} -> {:halt, put_flash(socket, :error, "Could not move that task there.")}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}
end
