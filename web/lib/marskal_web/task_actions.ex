defmodule MarskalWeb.TaskActions do
  @moduledoc """
  Complete and reopen on a task list.

  `reload` is called with the socket after the task changes and when another
  write arrives. `missing` is the flash when the task is gone; without it,
  that case says the update failed.
  """

  defmacro __using__(opts) do
    reload = Keyword.fetch!(opts, :reload)
    missing = Keyword.get(opts, :missing)

    quote do
      @impl true
      def handle_info({:marskal_change, _type, _id}, socket) do
        {:noreply, unquote(reload).(socket)}
      end

      @impl true
      def handle_event(action, %{"id" => id}, socket) when action in ["complete", "reopen"] do
        fun =
          if action == "complete",
            do: &Marskal.Tasks.complete_task/3,
            else: &Marskal.Tasks.reopen_task/3

        MarskalWeb.TaskActions.act(socket, id, fun, unquote(missing), unquote(reload))
      end
    end
  end

  @doc false
  def act(socket, id, fun, missing, reload) do
    case fun.(socket.assigns.current_scope.user, id, Ecto.UUID.generate(version: 7)) do
      {:ok, _} ->
        {:noreply, reload.(socket)}

      {:error, :not_found} ->
        {:noreply,
         Phoenix.LiveView.put_flash(socket, :error, missing || "Could not update task.")}

      {:error, _} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Could not update task.")}
    end
  end
end
