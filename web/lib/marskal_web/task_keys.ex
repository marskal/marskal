defmodule MarskalWeb.TaskKeys do
  @moduledoc """
  Keyboard actions on a focused task (ADR 0031): check, drop, and flag.

  The `.Outline` hook sends them from whichever keymap is in use. A change
  broadcasts, and the list's own handler reloads. Check does what the
  checkbox does. Drop says so, since the key needs no confirmation; the
  row stays on the list, and Check reopens it.
  """

  use Gettext, backend: MarskalWeb.Gettext

  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  alias Marskal.Tasks

  def attach(socket) do
    attach_hook(socket, :task_keys, :handle_event, &handle_event/3)
  end

  defp handle_event("task-check", %{"id" => id}, socket) when is_binary(id) do
    case task(socket, id) do
      nil -> failed(socket)
      %{state: :to_do} -> act(socket, id, %{state: :done})
      _task -> act(socket, id, %{state: :to_do})
    end
  end

  defp handle_event("task-drop", %{"id" => id}, socket) when is_binary(id) do
    case task(socket, id) do
      nil ->
        failed(socket)

      %{state: :dropped} ->
        {:halt, socket}

      task ->
        case Tasks.drop_task(socket.assigns.current_scope.user, id, command_id()) do
          {:ok, _} ->
            {:halt, put_flash(socket, :info, gettext("Dropped “%{title}”.", title: task.title))}

          {:error, _} ->
            failed(socket)
        end
    end
  end

  defp handle_event("task-flag", %{"id" => id}, socket) when is_binary(id) do
    case task(socket, id) do
      nil -> failed(socket)
      task -> act(socket, id, %{flagged: not task.flagged})
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp task(socket, id), do: Tasks.get_task(socket.assigns.current_scope.user, id)

  defp act(socket, id, attrs) do
    case Tasks.update_task(socket.assigns.current_scope.user, id, attrs, command_id()) do
      {:ok, _} -> {:halt, socket}
      {:error, _} -> failed(socket)
    end
  end

  defp failed(socket),
    do: {:halt, put_flash(socket, :error, gettext("Could not update task."))}

  defp command_id, do: Ecto.UUID.generate(version: 7)
end
